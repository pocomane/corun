
# Corun

Corun is an extremely simple Bash script designed to run minimal container. It
does not use OCI images, Docker, Podman, or any other container "Management"
software. Instead, it simply launches a BusyBox executable via BubbleWrap.

The command:

~~~
./corun.sh <cmd> [arg1] ... [argN]
~~~

will automatically downloads busybox and bwrap on the first run. It then
executes your command within the isolated environment. By default, you can run
any standard BusyBox tool as the `<cmd>`.

The container root filesystem is stored in the `cache/container/` directory
relative to the script.

If you do not have `corun.sh` locally, you can download and run it with the
one-liner:

~~~
curl -o - https://raw.githubusercontent.com/pocomane/corun/refs/heads/main/corun.sh | sh
~~~

# Better environment

At the end of the script, there is a section for commands to be executed inside
the container right before each run. The default script does nothing useful,
but you can use it to set up a better environment. For example, you can
download an image of a distribution with a package manager that allows you
to easily install additional software.

For Alpine Linux, you can use something like this:

~~~
container_prerun(){
exec 3<<'EOF'
#!/coresys/busybox sh

set -e

DISTRO_IMAGE="http://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-minirootfs-3.21.3-x86_64.tar.gz"

if [ ! -f "/bin/sh" ]; then
  mkdir -p /image-temp
  cd /image-temp
  wget -O - "$DISTRO_IMAGE" | tar -xzf -
  cd -
  cd /
  yes n | cp -Ri image-temp/./ ./
  rm -fR image-temp
  cd -
fi

apk add binutils git

if [ "$#" -gt 0 ] ; then
  exec "$@"
else
  exec sh
fi

EOF
}
~~~

and then install additional software with

~~~
./corun.sh apk add my-needed-app
~~~

For Ubuntu:

~~~
container_prerun(){
exec 3<<'EOF'

set -e

DISTRO_IMAGE="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-root.tar.xz"

if [ ! -f "/bin/sh" ]; then
  mkdir -p /image-temp
  cd /image-temp
  wget -O - "$DISTRO_IMAGE" | tar -xJf -
  rm -fR dev proc sys run boot
  cd -
  cd /
  yes n | cp -Ri image-temp/./ ./
  rm -fR image-temp
  cd -
  echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99no-drop-privs
fi

apt-get update
apt-get install -y binutils git

if [ "$#" -gt 0 ] ; then
  exec "$@"
else
  exec sh
fi

EOF
}
~~~

# Command option

Set IMAGE_MODE to bootstrap if you want use a fallback image extracted from
Alpine linux packages instead of the one downaloaded by the `corun` GitHub
repository. This is provided mainly for bootstrapping (See the section about
the image compilation)

Set CORUN_X environment to yes to enable X server applications.

Put in the CORUN_ATTACH environment variable a pid of a container process to
attach to a previously launched container. The pid must be the one seen in the
host, not in the contaier itself. When a container starts it reports a suitable
pid, refering to a process lasting until the end of that session.

Set CORUN_INIT to yes to let the script run busybox init as pid 1, then run
your app in that environment. This let you to write long running script that
spawn complex proces tree without the risk of accumulate defunct processes.

Set CORUN_KEEP_CHILD to yes to avoid the whole process subtree to be killed
when the main shell exit (useful with tmux, abduco, etc).

# Compiling the Image

By default, the busybox and bwrap binaries are downloaded from the project's
GitHub release page. Such image can be built using `make_container_binary.sh`,
which fetches the latest versions of all the needed software:

~~~
./corun.sh sh ./make_container_binary.sh
~~~

Since corun.sh normally attempts to download binaries from GitHub, you may need
an alternative if the GitHub releases are unavailable or broken. You can use
the "bootstrap" mode to set up a compatible image using Alpine Linux packages:

~~~
IMAGE_MODE="bootstrap" ./corun.sh sh ./make_container_binary.sh
~~~

In any case the image will be generated in `cache/build/container`, if you
rename it to `cache/container` you will be able to run the container with the
software just built.

