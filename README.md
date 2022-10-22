# Shonion : one-liner reverse SSH via Tor

This is a tool for debugging CI containers or other remote machines behind a NAT,
by running sshd and publishing it as a Tor hidden service. It prints a magic base64
string to stdout, which you then copy and paste into your terminal, to connect
to the remote machine :)

All of this is only possible because of the amazing work of @MagicalBitcoin to
compile Tor into a Rust crate and library that can be compiled to a static executable:

- https://github.com/MagicalBitcoin/libtor
- https://github.com/MagicalBitcoin/libtor-sys

This repository is a smaller Rust wrapper around `libtor` to run it in the CLI,
and a [POSIX shell (`.sh`) script](./shonion.sh) to add relatively cross-platform
"one liner" magic, assuming your platform has or can install packages like `openssh`, `nc` and `curl`.

## Try it

On a CI machine or remote environment, run this one-liner:

```bash
curl -sLf https://raw.githubusercontent.com/milesrichardson/shonion/main/shonion.sh | bash -s -- --listen
```

if all goes well, it will eventually print a base64 encoded "one-liner" for connecting to it, which will look something like:

```bash
bash <(echo "BiGLoNGBase64StringForYouToCopyIyEvdXNyL2JpbY3QgIiRAIgo=" | base64 -d)
```

Paste that into a terminal somewhere else, pour yourself some Red Bull, and
you'll end up in a stable shell session on the remote machine!

## How it works

- **The CI machine** runs `./shonion.sh --listen` which:

  - downloads and installs and dependencies required
  - downloads the static `shonion` binary to `~/.shonion/shonion`
  - runs the `shonion` binary in the background with default parameters to
    - run a SOCKS proxy on `127.0.0.1:19050`
    - create an Onion v3 service port forwarding `:34567` to `127.0.0.1:5678`
  - waits for connectivity to the Tor network including successful `.onion` connection back to itself
  - generates temporary SSH keypair, server configuration, and client bootstrap script
  - prints base64 encoded client bootstrapping script to stdout for easy copy/paste
  - starts a standalone sshd process in the foreground

- **The developer** pastes the base64 code from the CI machine into their terminal ;) which:
  - sets env var values containing the private keys and onion address
  - downloads `shonion.sh` from github
  - forks to `./shonion.sh --connect` which:
    - expects the env vars to be set containing private keys and onion address etc
    - repeats all the steps from `./shonion.sh --listen` but does not start sshd server
    - forks to ssh client that connects to the server

## Disclaimer

This is a toy project that's also useful, assuming you don't use it for anything
stupid, which I would not be responsible for.

This is intended for debugging purposes in throwaway environments like CI runners. However, it still prints a string and asks you to execute it on your developer machine, which you should always be careful about doing. Also, it prints the temporary private keys to stdout, so be careful who sees those, since they contain all the information necessary to connect to the machine. All the same warnings about leaking env vars in CI runners apply, except that these env vars also let someone who sees the logs connect to the machine and access any "more secret" env vars.

## What's in the repo

There are two parts to this:

- The rust crate `shonion` which is a tiny wrapper around [`libtor`](https://github.com/MagicalBitcoin/libtor) and compiles to a static executable (which we currently just check into the repository)
- The POSIX shell (`.sh`) script `shonion.sh` which wraps the `shonion` binary to start it in the background while running `sshd` (`--listen`) or `ssh` (`--connect`) in the foreground.

As a "one liner", the script can be downloaded directly from its raw GitHub URL.
Similarly, when the `--listen` script prints a bootstrapping script for the client
to copy/paste, that script will also ultimately download `shonion.sh` from GitHub.
(In the future, this could be reduced to only needing the `shonion` binary, and keys
could be exchanged via a temporary Onion service before establishing the connection)

# How to Use

## Running standalone as a pair of one-liners

In general, the goal is for `./shonion.sh --listen` to be as standalone and
autonomous as possible, because we assume that's running on some automated
system like a CI machine where manual intervention is impossible. It tries
to download missing packages using whatever package manager it can find,
and waits to be sure connetivity is up before printing keys for client.

The `./shonion.sh --connect` script can be more interactive, since we assume that
it's running on the developer's machine. However, at the moment it's all or nothing,
and if the connection fails you need to rerun the whole thing again. This is next
to improve.

### Download script from GitHub

This is the command at the top of the readme. On the server, run:

```
curl -sLf https://raw.githubusercontent.com/milesrichardson/shonion/main/shonion.sh | bash -s -- --listen
```

On the client, run the command it prints for you.

### Clone repository from GitHub

```
https://github.com/milesrichardson/shonion.git
./shonion.sh --listen
```

Note: this will still download the `shonion` binary separately to
`~/.shonion/shonion`. If you want to build the repository and use the `shonion`
binary, then set `SHONION_BIN` to the location of the binary before you
run the script, e.g.

```bash
SHONION_BIN="$(pwd)"/bin/static/x86_64-unknown-linux-gnu/shonion
```

However, this will also write some files to the current directory. So you may
want to just move that binary to your home directory yourself.

### Between two Docker containers

The easiest way to try this repository might be to use it between two Docker
containers on the same machine. The only requirement is that they can both
connect to the internet. Also, make sure the client container has `curl` installed
before you paste the command printed out by the listener.

Launch two conainers with:

```
docker run -u root --rm -it ubuntu:20.04 bash
```

And then just follow the one-liner instructions above. In the client container,
make sure you install `curl` (`apt-get update -qq && apt-get install -yy curl`)
before pasting the base64 encoded command.

## Troubleshooting

### Can't connect

Try running manually following the instructions below.

Try deleting the Tor state and running again:

```
rm -rf /tmp/tor-rust
```

check the logs of Tor output:

```
cat ~/.shonion/shonion.stdout.log
```

### Zombie processes

If you are running multiple times on the client, sometimes the process handling
doesn't work as well as it should. A few that can get stuck running in the
background are `shonion`, `shonion.sh` and `tail -f ~/.shonion/shonion.stdout.log`

Usually `pkill -f shonion` will kill any of them.

## Running Manually

The one-liner scripts are nice, especially on the server, where it is relatively
stable and will usually work well.

But it can be annoying on the client when it makes it all the way through but then
times out on the SSH connetion, or if you want to do anything differently with the
SSH client other than just connect to it.

Ultimately, you can do everything in the script manually.

### Run "`shonion`" (really Tor) in the background

In the background, or some terminal somewhere, run the `shonion` binary. Both
the client and server need to do this, because it's the process that establishes
connectivity to the Tor network.

You can run `shonion --help` to see the args, or just read `main.rs`. This will
connect to the Tor network, start the Tor SOCKS proxy, and create a hidden
service with port forwarding `.onion:34567 -> 127.0.0.1:5678`. It also creates
a directory at `/tmp/tor-rust` for storing Tor state, which it will re-use on
subsequent invocations if it exists.

Run Shonion (`--help` to see params):

```bash
./bin/static/x86_64-unknown-linux-gnu/shonion
```

Find the generated `.onion` name:

```bash
cat /tmp/tor-rust/hs-dir/hostname
```

Delete the Tor state (sometimes it helps to do this before running `shonion`):

```bash
rm /tmp/tor-rust
```

### On the server

On the server, you need to run some listener on port `5678`, which is where
your Onion service is forwarding traffic to. This can be as simple
as `nc -l 127.0.0.1 5678` or `python -m http.server 5678` or a full blown sshd
server.

You can read [`shonion.sh`](./shonion.sh) (ctrl+f for `sshd`) to see the arguments
it uses to run `sshd`. Here's what it looks like at the time of writing:

```bash
usr/sbin/sshd -f /dev/null -e -D \
-o ListenAddress=127.0.0.1:5678 \
-o StrictModes=no \
-o HostKey="$SHONION_LISTENER_ROOT"/ssh_host_rsa_key \
-o PidFile="$SHONION_LISTENER_ROOT"/sshd.pid \
-o AuthenticationMethods=publickey \
-o KbdInteractiveAuthentication=no \
-o ChallengeResponseAuthentication=no \
-o PasswordAuthentication=no \
-o UsePAM=no \
-o AuthorizedKeysFile="$SHONION_LISTENER_ROOT"/authorized_keys
```

### On the client

The client also needs to run `shonion` in the background, so it can use the
SOCKS proxy to connect through Tor to the onion service.

Basically, you need to ensure whatever command you're running (`curl`, `nc`, `ssh`,
etc.) will defer hostname resolution to the proxy.

Then, the client can run whatever it wants to connect to that Onion service,
like how `shonion.sh` runs an `ssh` client.

#### `ssh` manually

Here is the command we use in `shonion.sh`:

```bash
ssh -v \
    -F /dev/null \
    -o IdentityFile="$(pwd)"/id_shonion_client_rsa \
    -o IdentitiesOnly=yes \
    -o ConnectTimeout=120 \
    -o StrictHostKeychecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o "proxyCommand=nc -x 127.0.0.1:19050 -X 5 %h %p" \
"$SHONION_CLIENT_SSH_USER"@"$SHONION_CLIENT_DEST_ONION_HOST" -p "$SHONION_CLIENT_DEST_ONION_PORT"
```

You can also add keys to an SSH config file, which might look something like
this:

```
Host hidden
    User root
    IdentityFile /tmp.blahblah/id_shonion_client_rsa
    StrictHostKeychecking no
    UserKnownHostsFile /dev/null
    hostname ukni7gxoz2fhmox2hp7yfatnoykfycxgseckljtm2553myiwvytawead.onion
    proxyCommand nc -x 127.0.0.1:9150 -X 5 %h %p
```

#### `curl` through SOCKS to clearnet

```bash
curl -q --socks5-hostname 127.0.0.1:19050 https://www.cloudflare.com/cdn-cgi/trace
```

#### `curl` through SOCKS to your own Onion service

Start a server to listen on the port where Tor is forwarding requests to your
hidden services:

```bash
python -m http.server 5678
```

Send a request to that hidden service on the port where Tor is exposing it:

```bash
curl -q --socks5-hostname 127.0.0.1:19050 "http://$(cat /tmp/tor-rust/hs-dir/hostname):34567"
```

#### `netcat` through SOCKS back to itself via Onion

Create a listener on your own machine at the port where Tor is forwarding requests to your hidden service, then send a packet to its address. This will make a round-trip across the Tor network back to itself (in theory, it should be ~6 proxies depending on entry guard config, i.e. 3 to the destination and then 3 back to the source).

```
start=$(date +%s) ; NC_PID="$(nc -vrl 127.0.0.1 5678 >/dev/null 2>/dev/null & echo $! )" \
    && nc -tvz -x 127.0.0.1:19050 -X 5 "$(cat /tmp/tor-rust/hs-dir/hostname)" 34567 \
    && echo "success in $(($(date +%s)-start)) seconds" \
    && { kill "$NC_PID" || true ; } && echo ok
```

# Development

Note: we are using the Git URL for `libtor` in `Cargo.toml` because at the time
of writing, the published version at `crates.io` is not the most recent commit.

## Rust development and binary management

Regular Cargo commands work. There are also a few scripts for automating the
build and "staging" (commiting to this repo lol) of the binary:

### NIH and YAGNI scripts

#### Check your host triple (requires `rustc`):

```sh
./scripts/get-host-triple.sh
```

#### Find the `bin/{static,dynamic}/shonion` executable:

```sh
./scripts/get-shonion-executable.sh static
# -> bin/static/x86_64-apple-darwin/shonion

./scripts/get-shonion-executable.sh dynamic
# -> bin/dynamic/x86_64-apple-darwin/shonion
```

#### Link binary from repository without building it

If you've checked out the repository and it already has a binary compiled
for your architecture in `bin/{static,dynamic}/$your_architecture/shonion`
then you can create a symlink `shonion` pointing to it:

```bash
./link.sh
```

This will try to guess your architecture using the code in `./scripts/get-shonion-executable.sh`. Note it depends on having `rustc` installed.

Then it will run the appropriate `ln` command to link the binary, for example:

```
ln -s shonion bin/static/x86_64-unknown-linux-gnu/shonion
```

#### Build binary for static and dynamic versions

Build static and dynamic versions. The static version is usually preferable, and
it uses static linking of vendored dependencies for `openssh`, `lzma` and `zstd`

For more information, see the [Cross Compiling docs from `libtor-sys`](https://github.com/MagicalBitcoin/libtor-sys/blob/master/CROSS_COMPILING.md).

```bash
# Build both dynamic and static target
./scripts/build-all.sh

# Only static:
./scripts/build.sh

# Only dynamic
BUILD_DYNAMIC=1 BUILD_STATIC=0 ./scripts/build.sh
```

#### Copy compiled executable to `bin` and show resulting Git diff

Move those new versions into `bin/{static,dynamic}/{host_arch}/shonion`

(also temporarily stage each file to show its diff, but don't commit)

```bash
./scripts/stage-release.sh
```

#### Stage the new files in `bin` and author a commit message for each

Stage those changes again, but actually commit them this time:

```bash
./scripts/stage-release.sh --commit
```

## Other Resources

- `libtor`

  - [readme](https://github.com/MagicalBitcoin/libtor)

- `libtor-sys`

  - [readme](https://github.com/MagicalBitcoin/libtor-sys)
  - [cross-compiling](https://github.com/MagicalBitcoin/libtor-sys/blob/master/CROSS_COMPILING.md)
  - [`ci.yaml` github workflows](https://github.com/MagicalBitcoin/libtor-sys/blob/master/.github/workflows/ci.yaml) (for compilation examples)

- Tor
  - [Tor manual](https://2019.www.torproject.org/docs/tor-manual.html.en) (`.torrc` reference)

## Similar

This is not a new idea. Here are some other similar projects:

- torsh: same idea, but idk where those static binaries came from

  - https://github.com/pisoj/torsh

- `tor-socks-proxy` : dockerized socks proxy, works well

  - https://github.com/PeterDaveHello/tor-socks-proxy

- tor embedded in golang (outdated, no v3 support)

  - https://github.com/atorrescogollo/offensive-tor-toolkit

- `docker-tor-hidden-service`: everything in a dockerfile

  - https://github.com/cmehay/docker-tor-hidden-service/blob/master/Dockerfile

- `docker-onion-service`: simpler verison of dockerized hidden service
  - https://github.com/fphammerle/docker-onion-service
