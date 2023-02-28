# bira.sh

script for automatic GCP image deprecation

## Usage

```bash
❯ ./bira.sh
Usage: ./bira.sh [options] <command> [image-family ...]
Commands
  list-families    show image families
  list             show ALL images or specific families
  process          rotate images and set the state
                   by default keeps the last 3 images, mark the rest DELETED
    --advanced     advanced image tagging for gradual deprecation strategy
                   last=ACTIVE, last-1=DEPRECATED, last-2=OBSOLETE, rest are marked DELETED
  delete           delete images in DELETED state

Options
  --debug          show debug information
  --verbose        show state changes (output is to file descriptor 3)
  --dry-run        do not execute, just show commands
  --help           this

Environment Variables
  MAX_ACTIVE       limit the number of ACTIVE images, default 3, default advanced 1

Advanced processing only
  MAX_DEPRECATE    limit the number of DEPRECATE images, default 1
  MAX_OBSOLETE     limit the number of OBSOLETE images, default 1
```

* Most commands can be run with specific families
* Information is output to STDERR so STDIN can be piped and processed
* GCP project can be exported or declared for each invocation

```bash
❯ export CLOUDSDK_CORE_PROJECT=xxx
# or
❯ CLOUDSDK_CORE_PROJECT=xxx bira.sh
```

## Examples

### `list-families`

Self explanatory, mostly for internal use

```bash
❯ ./bira.sh list-families
anycast-dns
master-node
mx-node
nfs-node
recursor-node
scrubber
scrubber-api
```

### `list`

* List all images if no arguments are given

```bash
❯ ./bira.sh list
anycast-dns-20220331104913
anycast-dns-20220523072539
anycast-dns-20220826105355
anycast-dns-20220921130949
anycast-dns-20221018141110
anycast-dns-20230222142035
master-node-20230215164813
master-node-20230216105454
master-node-20230222162121
master-node-20230222164812
mx-node-20230215161912
...
```

* List only specific families

```bash
❯ ./bira.sh list scrubber scrubber-api
scrubber-20230227160125
scrubber-20221104081352
scrubber-20221101083506
scrubber-20221024125023
scrubber-api-20230227155319
scrubber-api-20221104080752
scrubber-api-20221103131837
scrubber-api-20221101082916
scrubber-api-20221024114720
```

### `process`

Process supports --dry-run to only show the gcloud commands without running them:

* Dry run two families

```bash
❯ ./bira.sh --dry-run process anycast-dns cdn-edge
gcloud compute images deprecate anycast-dns-20230222142035 --state ACTIVE
gcloud compute images deprecate anycast-dns-20221018141110 --state ACTIVE
gcloud compute images deprecate anycast-dns-20220921130949 --state ACTIVE
gcloud compute images deprecate anycast-dns-20220826105355 --state DELETED
gcloud compute images deprecate anycast-dns-20220523072539 --state DELETED
gcloud compute images deprecate anycast-dns-20220331104913 --state DELETED

gcloud compute images deprecate cdn-edge-20230227081621 --state ACTIVE
gcloud compute images deprecate cdn-edge-20230220080651 --state ACTIVE
gcloud compute images deprecate cdn-edge-20230213081208 --state ACTIVE
gcloud compute images deprecate cdn-edge-20230206074938 --state DELETED
gcloud compute images deprecate cdn-edge-20230131065511 --state DELETED
```

* Dry-run two families with advanced strategy, hide the commands and just show the state change:

```bash
❯ MAX_ACTIVE=2 MAX_DEPRECATE=0 MAX_OBSOLETE=2 ./bira.sh --dry-run --verbose  process --advanced anycast-dns cdn-edge >/dev/null
ACTIVE: anycast-dns-20230222142035
ACTIVE: anycast-dns-20221018141110
OBSOLETE: anycast-dns-20220921130949
OBSOLETE: anycast-dns-20220826105355
DELETED: anycast-dns-20220523072539
DELETED: anycast-dns-20220331104913
ACTIVE: cdn-edge-20230227081621
ACTIVE: cdn-edge-20230220080651
OBSOLETE: cdn-edge-20230213081208
OBSOLETE: cdn-edge-20230206074938
DELETED: cdn-edge-20230131065511
```

### `delete`

This is supposed to execute or show the commands for all images in DELETE state.
The following examples assume there are process images that are set in DELETED state.

```shell
❯ echo Y | ./bira.sh --verbose delete scrubber
The following images will be deleted:
 - [scrubber-20221024125023]

Do you want to continue (Y/n)?
Deleted [https://www.googleapis.com/compute/v1/projects/xxx/global/images/scrubber-20221024125023].
```

## Automation

Target usage is mostly cronjob.

* Rotate images at 03:00 every Saturday

```cron
0 3 * * 6 /<path/to>/bira.sh process && echo Y | /<path/to>/bira.sh delete
```
