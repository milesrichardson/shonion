## shonion

This is a tool for debugging CI containers or other remote machines behind a NAT,
by running sshd and publishing it as a Tor hidden service.

This repository is only possible because of the amazing work of @MagicalBitcoin to
compile Tor into a Rust crate and library that can be compiled to a static executable:

- https://github.com/MagicalBitcoin/libtor
- https://github.com/MagicalBitcoin/libtor-sys

## Basic Idea

- The CI machine runs `./listen.sh` and it prints out an onion V3 address, call it `foobar.onion`
- The developer runs `./connect.sh foobar.onion`

## How it works:

- CI script runs `./listen.sh`
  - creates a temporary keypair and launches `sshd` as the current user
  - publishes a tor hidden service forwarding to that sshd instance
  - prints out (or notifies) a script for the client to call
- Developer copies script from CI pipeline and runs it, `./connect.sh foobar.onion`
  - starts a tor client with socks proxy exposed
  - forks to an ssh client using socks5 proxy over tor to connect to onion site

boom, full-featured ssh session in a remote machine

## Link it

If you are using a platform with a binary checked into `bin`, then you don't
need to build it. Instead, just run `link.sh` to create a symlink at `shonion`
in the repo root.

```bash
./link.sh
```

## Build it

Build static and dynamic versions

```bash
# Build both dynamic and static target
./scripts/build-all.sh

# Only static:
./scripts/build.sh

# Only dynamic
BUILD_DYNAMIC=1 BUILD_STATIC=0 ./scripts/build.sh
```

Move those new versions into `bin/{static,dynamic}/{host_arch}/shonion`

(also temporarily stage each file to show its diff, but don't commit)

```bash
./scripts/stage-release.sh
```

Stage those changes again, but actually commit them this time:

```bash
./scripts/stage-release.sh --commit
```

## Troubleshooting / Other Scripts

Check your host triple (requires `rustc`):

```sh
./scripts/get-host-triple.sh
```

Find the `bin/{static,dynamic}/shonion` executable:

```sh
./scripts/get-shonion-executable.sh static
# -> bin/static/x86_64-apple-darwin/shonion

./scripts/get-shonion-executable.sh dynamic
# -> bin/dynamic/x86_64-apple-darwin/shonion
```

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
