#!/usr/bin/env bash
# Build Image Rotation Automation
# https://cloud.google.com/compute/docs/images/deprecate-custom#deprecation-states
gcp=gcloud

function usage {
  set +x
  export PS4='+ '
  echo "Usage: ${BASH_SOURCE[0]} [options] <command> [image-family ...]"
  echo $'Commands'
  echo $'\tlist-families  \tshow image families'
  echo $'\tlist           \tshow ALL images or specific families'
  echo $'\tprocess        \trotate images and set the state'
  echo $'\t               \tby default keeps the last 3 images, mark the rest DELETED'
  echo $'\t  --advanced   \tadvanced image tagging for gradual deprecation strategy'
  echo $'\t               \tlast=ACTIVE, last-1=DEPRECATED, last-2=OBSOLETE, rest are marked DELETED '
  echo $'\tdelete         \tdelete images in DELETED state'
  echo
  echo 'Options'
  echo $'\t--debug        \tincrease verbosity'
  echo $'\t--dry-run      \tdo not execute, just show commands'
  echo $'\t--help         \tthis help'
  echo $'\t--verbose      \tmore information'
  echo
  echo 'Environment Variables'
  echo $'\tMAX_ACTIVE     \tlimit the number of ACTIVE images, default 3, default advanced 1'
  echo
  echo 'Advanced processing only'
  echo $'\tMAX_DEPRECATE  \tlimit the number of DEPRECATE images, default 1'
  echo $'\tMAX_OBSOLETE   \tlimit the number of OBSOLETE images, default 1'
  echo
  exit
}

function debug {
  export PS4=$'+($0:${LINENO}) ${FUNCNAME[1]:+${FUNCNAME[1]}(): }'
  set -x
  main "$@"
}

function fail { if [[ "$1" ]]; then echo "ERROR: Unknown command $1"; fi; usage; }

function gcp_images_list {
  local format="$1"
  shift
  local args="$*"
  ${gcp} compute images list --show-deprecated --no-standard-images --format="${format}" "${args}" | sort -r
}

function gcp_image_change_deprecate_status {
  local image=$1 state=$2
  ${dryrun:+echo} echo "${gcp}" compute images deprecate "${image}" --state "${state}"
}

function list_families {
  local format_string='value(family)'
  gcp_images_list "${format_string}" --filter='name:*' | sort -u | grep -v '^$'
}

function list_family_images  {
  local family=$1
  local format_string='value(name)'
  local filter_string="family<=${family} AND family>=${family}"
  gcp_images_list "${format_string}" --filter="${filter_string}"
}

function list_images_for_deletion {
  local family=$1
  local format_string='value(name)'
  local filter_string="family<=${family} AND family>=${family} AND deprecated.state=DELETED"
  gcp_images_list "${format_string}" --filter="${filter_string}"
}

function delete_family_images {
  local images_for_deletion family=$1
  mapfile -t images_for_deletion < <(list_images_for_deletion "${family}")
  ${dryrun:+echo} echo "${gcp}" compute images delete "${images_for_deletion[@]}"
}

function loop_images_in_family {
  local family_images=() image family=$1
  local ACTIVE=() OBSOLETE=() DEPRECATE=() DELETED=()
  local -n status
  mapfile -t family_images < <(list_family_images "${family}" | sort -r)
  if [[ "${advanced}" -ne 1 ]]; then
    ACTIVE=("${family_images[@]:0:${MAX_ACTIVE:-3}}")
    DELETED=("${family_images[@]:${MAX_ACTIVE:-3}}")
  else
    for image in "${family_images[@]}"; do
      if   [[ "${#ACTIVE[@]}"    -lt "${MAX_ACTIVE:-1}"    ]]; then
        ACTIVE+=("${image}")
      elif [[ "${#DEPRECATE[@]}" -lt "${MAX_DEPRECATE:-1}" ]]; then
        DEPRECATE+=("${image}")
      elif [[ "${#OBSOLETE[@]}"  -lt "${MAX_OBSOLETE:-1}"  ]]; then
        OBSOLETE+=("${image}")
      else
        DELETED+=("${image}")
      fi
    done
  fi
  unset image
  for status in ACTIVE DEPRECATE OBSOLETE DELETED; do
    if [[ -n "${status[0]}" ]]; then
      for image in "${status[@]}"; do
        gcp_image_change_deprecate_status "${image}" "${!status}"
        if [[ "${verbose}" -eq 1 ]]; then
          >&2 printf "${!status}: %s\n" "${image}"
        fi
      done
    fi
  done | column -t
  echo
}

function loop_families {
  local action=$1
  shift
  local family family_list
  if [[ -z "$*" ]]; then
    mapfile -t family_list < <(list_families)
  else
    family_list=("$@")
  fi
  for family in "${family_list[@]}"; do
    if [[ -z "${family}" ]]; then continue; fi
    "${action}" "${family}"
  done
}

function main {
  local arg=$1
  shift
  case "${arg}" in
               --debug) debug                               "$@";;
    --dryrun|--dry-run) dryrun=1;  main                     "$@";;
             --verbose) verbose=1; main                     "$@";;
                --help) usage;;
                  list) if [[ -z "$*" ]]; then
                          gcp_images_list 'value(name)' --filter='name:*'
                        else
                          loop_families list_family_images  "$@"
                        fi;;
         list-families) list_families;;
                delete) loop_families delete_family_images  "$@";;
               process) if [[ "$1" == '--advanced' ]]; then local advanced=1; shift; fi
                        loop_families loop_images_in_family "$@";;
                     *) fail "${arg}";;
  esac
  set +x
}

main "$@"
