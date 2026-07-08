#!/bin/sh
# #############################################################################
# THIS is a container launcher utility. It may contain application
# specific code runned into the container in the `container_prerun` function.
# See github.com/pocomane/corun for more information.
# #############################################################################
# Boilerplate
set -e
SCRDIR="$(cd -P -- "$(dirname "$0")" && pwd)" # for path add /$(basename "$0")

# #############################################################################
# Configuration

HOST_SCRIPT_DIR="$SCRDIR"
CONT_WORK_DIR="/share"
IMAGE_FS="cache/container"
CHECK_FOLDER="$HOST_SCRIPT_DIR/$IMAGE_FS"
CORESYS_FOLDER="coresys" # At root of container filesystem
IMAGE_MODE="${IMAGE_MODE:-release}" # supported values: release (default) or bootstrap (fallback)
GUEST_PRERUN_PATH="/tmp/container_prerun.sh"
GUEST_INITSCRIPT_PATH="/tmp/inittab_script.sh"
GUEST_SHARE_PATH="./"

# #############################################################################
# Launcher utility

AUX_RELEASE_IMAGE="https://github.com/pocomane/corun/releases/latest/download/container.tar.gz"
AUX_BUSYBOX_BOOTSTRAP="https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/busybox-static-1.36.1-r31.apk"
AUX_BUSYBOX_SUBPATH="bin/busybox.static"
AUX_BWRAP_BOOTSTRAP="https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/bubblewrap-static-0.11.2-r0.apk"
AUX_BWRAP_SUBPATH="usr/bin/bwrap.static"

download(){
  #wget -O - --no-check-certificate "$1"
  wget -O - "$1"
}

create_container_image_bootstrap(){

  mkdir -p "$HOST_SCRIPT_DIR/$IMAGE_FS/$CORESYS_FOLDER"

  mkdir -p "$HOST_SCRIPT_DIR/$IMAGE_FS/torem"
  cd "$HOST_SCRIPT_DIR/$IMAGE_FS/torem"
  download "$AUX_BUSYBOX_BOOTSTRAP" | tar -xzf -
  cp "$AUX_BUSYBOX_SUBPATH" "$HOST_SCRIPT_DIR/$IMAGE_FS/$CORESYS_FOLDER"/busybox
  cd -
  rm -fR "$HOST_SCRIPT_DIR/$IMAGE_FS"/torem

  mkdir -p "$HOST_SCRIPT_DIR/$IMAGE_FS/torem"
  cd "$HOST_SCRIPT_DIR/$IMAGE_FS/torem"
  download "$AUX_BWRAP_BOOTSTRAP" | tar -xzf -
  cp "$AUX_BWRAP_SUBPATH" "$HOST_SCRIPT_DIR/$IMAGE_FS/$CORESYS_FOLDER"/bwrap
  cd -
  rm -fR "$HOST_SCRIPT_DIR/$IMAGE_FS"/torem

  cd "$HOST_SCRIPT_DIR/$IMAGE_FS/$CORESYS_FOLDER"
  ./bwrap --bind ../ / -- "/$CORESYS_FOLDER/busybox" --install -s "/$CORESYS_FOLDER/"
  cd -
}

create_container_image_release(){
  mkdir -p "$HOST_SCRIPT_DIR/$IMAGE_FS"
  cd "$HOST_SCRIPT_DIR/$IMAGE_FS"
  download "$AUX_RELEASE_IMAGE" | tar -xzf -
  cd -
}

LAST_FD=5 # 0-2 are standard FD, 3 is used for container_prerun, 4-5 are used for busibox init trick
open_file_descriptor() {
  if [ "$1" = "from_file" ] ; then # Open the file in a FD and retun its number in a variable
    LAST_FD=$((LAST_FD + 1))
    eval "exec ${LAST_FD}<$3"
    eval "$2=${LAST_FD}"
  elif [ "$1" = "to_stdout" ] ; then # Open a FD, redirect it to stdout, and return its number in a variable
    LAST_FD=$((LAST_FD + 1))
    eval "exec ${LAST_FD}>&1"
    eval "$2=${LAST_FD}"
  fi
}

quote() {
    printf '%s\n' "$1" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/"
}

container_run(){

  # Put in the CORUN_X environment variable "yes" to enable X server applications
  # Put in the CORUN_ATTACH environment variable a pid to attach to its container

  CONTROOT="$HOST_SCRIPT_DIR/$IMAGE_FS/"
  CMDSIZ="$#"

  #    note:
  #    - "--cap-add ALL" should be removed for security reason (but it neess some time to find a
  #      good set of capability to keep)
  #    - "--newsession" should be add to avoid guest injecting command in the host terminal (but it
  #      give issues when you want use the container throug the host terminal)
  #    - instead of "--newsession", at least the TIOCSTI capability should be dropped
  #   -  we use --share-net (instead of --unshare-net) since it is most simple way to let
  #      the container interact with the rest of the world.
  #    - we do not use --unshare-all because it will add --unshare-user. We need the
  #      same user namespace to let the host system allow to do stuff with the same privilages of
  #      the caller user (e.g. if called by root, you can bind low port).
  #

  if [ "$CORUN_EXTRA_BIND_SOURCE" != "" -a "$CORUN_EXTRA_BIND_DESTINATION" != "" ] ; then
    set -- "$@" \
      --bind "$CORUN_EXTRA_BIND_SOURCE"/ "$CORUN_EXTRA_BIND_DESTINATION"/
  fi

  if [ "$CORUN_X" = "yes" ] ; then
    if [ "$XAUTHORITY" = "" ] ; then XAUTHORITY="$HOME/.Xauthority"; fi
    set -- "$@" \
      --setenv DISPLAY "$DISPLAY" \
      --bind "$XAUTHORITY" /root/.Xauthority
    # Other option maybe useful:
    #   --bind /tmp/.X11-unix /tmp/.X11-unix
    #   --bind /dev/dri /dev/dri
    #   --bind /dev/snd /dev/snd
    # To reuse the fonts of the host:
    #   --ro-bind /usr/share/fonts /usr/share/fonts
  fi

  set -- "$@" \
    \
    --cap-add ALL \
    --uid "0" \
    --gid "0" \
    \
    --share-net \
    --unshare-ipc \
    --unshare-uts \
    --unshare-cgroup \
    --clearenv \
    \
    --bind "$CONTROOT" / \
    --dev /dev \
    --tmpfs /run \
    --tmpfs /tmp \
    --bind /sys /sys \
    --proc /proc \
    --tmpfs /dev/shm \
    --bind /sys /sys \
    \
    --chdir "$CONT_WORK_DIR" \
    --setenv HOME /root \
    --setenv PATH "/bin:/usr/bin:/sbin:/usr/sbin:/$CORESYS_FOLDER"  \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --ro-bind /etc/hosts /etc/hosts \
    --ro-bind /etc/services /etc/services \
    \
    --bind "$GUEST_SHARE_PATH" "$CONT_WORK_DIR"

  # Set CORUN_KEEP_CHILD to anything to avoid the whole process subtree
  # to be killed when the main shell exit (useful with tmux, abduco, etc)
  if [ "$CORUN_KEEP_CHILD" = "" ] ; then
    set -- "$@" \
      --die-with-parent
  fi

  if [ "$CORUN_ATTACH" = "" ] ; then
    # NOTE : when using --as-pid-1 the luanched process must reap the zombies
    #        so probably you want it to be shor living or someting like init
    # NOTE : it seems that also without --as-pid-1 bwrap do not create a zombi
    #        reaper process with pid 1. Mor tests are needed
    open_file_descriptor to_stdout FD_INFO
    set -- "$@" \
      --info-fd $FD_INFO \
      --unshare-user \
      --unshare-pid
  else
    open_file_descriptor to_stdout FD_INFO
    open_file_descriptor from_file FD_PID /proc/"$CORUN_ATTACH"/ns/pid
    open_file_descriptor from_file FD_USER /proc/"$CORUN_ATTACH"/ns/user
    # What to do with other namespace? cgroup ipc mnt net pid_for_children time
    # time_for_children uts
    set -- "$@" \
      --info-fd $FD_INFO \
      --pidns $FD_PID \
      --userns $FD_USER
  fi

  container_prerun # This opens the FD 3 with code to run at startup of container
  # Then we mount it in a know position
  set -- "$@" \
    --perms 0700 --bind-data 3 "$GUEST_PRERUN_PATH"

  if [ "$CORUN_INIT" = "" ] ; then
    # Place original command at end of arguments as paramters of container_prerun
    set -- "$@" \
      "$GUEST_PRERUN_PATH"
    i=0 ; while [ "$i" -lt "$CMDSIZ" ] ; do
      arg=$1
      shift
      set -- "$@" "$arg"
      i=$((i + 1))
    done 
  else
    # Busybox init trick
    # Remove the original command, place it in the inittab,
    # and launch busybox init instead. The inittab and other
    # utility file are mounted with --bind-data creating
    # ad-hoc file descriptors
    CMD="" 
    i=0 ; while [ "$i" -lt "$CMDSIZ" ] ; do
      CMD="$CMD $(quote "$1")"
      shift # Remove original command
      i=$((i + 1))
    done
    # Place command in inittab
    exec 4<<EOF
::once:$GUEST_INITSCRIPT_PATH
EOF
    exec 5<<EOFFFFF
#!/coresys/busybox sh
trap 'kill -TERM 1' EXIT INT TERM # Close busybox init when exiting otherwise it will survive to its childen
cd $CONT_WORK_DIR
export PATH='$PATH:/coresys'
"$GUEST_PRERUN_PATH" $CMD
EOFFFFF
    # Launch busybox init instead
    set -- "$@" \
      --as-pid-1 \
      --perms 0777 --bind-data 5 "$GUEST_INITSCRIPT_PATH" \
      --bind-data 4 /etc/inittab \
      busybox init
    # Note : using a true minimal init like tiny o dumb-init would make this
    # simpler, without requiring binding anything, just launch it with the
    # script path at command line. Maybe we can add one of them to the image ?
  fi

  # set -x
  exec "$HOST_SCRIPT_DIR/$IMAGE_FS/$CORESYS_FOLDER"/bwrap "$@"
}

main(){
  basic_image_check="$CHECK_FOLDER/$CORESYS_FOLDER/container.done"
  if [ ! -e "$basic_image_check" ] ; then
    if [ "$IMAGE_MODE" = "release" ] ; then
      create_container_image_release
    else
      create_container_image_bootstrap
    fi
    touch "$basic_image_check"
  fi
  container_run "$@"
}

# #############################################################################
# Application specific code

container_prerun(){
exec 3<<'EOF'
#!/coresys/busybox sh

# This can be used to do operations in container when entering
# it, bofore running what requested from the command line.

set -e

# # This is an example using the Alpine Linux repo
# AUX_ALPINE_IMAGE="http://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-minirootfs-3.21.3-x86_64.tar.gz"
#
# if [ ! -f "/bin/sh" ]; then
#   mkdir -p /alpine-temp
#   cd /alpine-temp
#   wget -O - "$AUX_ALPINE_IMAGE" | tar -xzf -
#   cd -
#   cd /
#   yes n | cp -Ri alpine-temp/./ ./
#   rm -fR alpine-temp
#   cd -
#   apk add binutils file gcc g++ make
# fi

# Run the command the user provided at command line, or the default shell if
# missing. If you remove it the command line will not be execute, so you can
# use it to run always the same commands.
if [ "$#" -gt 0 ] ; then
  exec "$@"
else
  exec sh
fi

EOF
}

# #############################################################################
# Main dispatcher
main "$@"

