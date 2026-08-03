#!/bin/bash
# Like in-sl7.sh but sources the issue-491 clean repro setup instead of the
# workspace setup.sh, and runs in the issue-491 dir.
set -euo pipefail
IMG=/cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:latest
SETUP=/exp/icarus/app/users/yuhw/wcdev-icarus/issue-491/repro-setup.sh
RUNDIR=/exp/icarus/app/users/yuhw/wcdev-icarus/issue-491
APPTAINER=/cvmfs/oasis.opensciencegrid.org/mis/apptainer/current/bin/apptainer
exec "$APPTAINER" exec --ipc --pid \
    -B /cvmfs,/exp,/nashome,/opt,/run/user,/etc/hostname,/etc/hosts,/etc/krb5.conf \
    "$IMG" \
    /bin/bash -c "source '$SETUP' >/dev/null 2>&1 || true; cd '$RUNDIR' && \"\$@\"" \
    _ "$@"
