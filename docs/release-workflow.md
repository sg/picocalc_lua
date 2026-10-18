# Release workflow

`.forgejo/workflows/release.yml` turns a tag into a staged release. When a
tag matching `v*` is pushed (or the workflow is started by hand for an
existing tag) a job builds `picolua-<board>-<tag>.uf2` for all five boards
with `build.sh`, packs the SD-card files with `make-sd-archive.sh`, writes
`SHA256SUMS.txt`, and creates a **draft** release with those assets and the
commit list since the previous tag as notes. Nothing is public until the
draft is reviewed and published in the Forgejo UI.

The job runs in the `picocalc-builder` image, built from `ci/builder` in
the picocalc-z80 repository: Ubuntu 24.04 with the same
`gcc-arm-none-eabi` 13.2 package the development machine uses, Pico SDK
2.3.1 with its submodules and a matching picotool. The image tag is the
SDK version it carries, so a release is built against the SDK named in
the workflow. A run only needs network access to clone the tag and
upload the assets; the five compiles take roughly two minutes on a
four-core machine.

## One-time runner setup

Forgejo does not run jobs itself; a Forgejo Runner does. With Forgejo in a
compose stack on the NAS managed through Portainer, the simplest
arrangement is a runner service in the same stack that drives the NAS
Docker daemon through its socket, so jobs run as sibling containers next
to Forgejo and PostgreSQL. Portainer has no equivalent of
`docker compose run`, so the service registers itself on first start from
a token supplied as a stack environment variable.

1. Get a registration token from the repository's runner page,
   `http://192.168.27.9:3000/steve/picocalc_lua/settings/actions/runners`
   (a user-level token from `/user/settings/actions/runners` lets the same
   runner serve every repository instead).

2. In Portainer open the stack's editor and add the service below. It runs
   as the NAS user that owns `/volume1/docker/forgejo/runner` (uid 1026,
   gid 100) so everything it writes there stays owned by that user, and it
   joins group 0 because `/var/run/docker.sock` on the NAS belongs to
   root:root. `depends_on` names whatever the Forgejo service is called in
   the stack.

   ```yaml
     runner:
       image: code.forgejo.org/forgejo/runner:13.2.0
       restart: unless-stopped
       depends_on:
         - forgejo
       user: "1026:100"
       group_add:
         - "0"
       environment:
         RUNNER_TOKEN: ${RUNNER_TOKEN}
         FORGEJO_URL: ${FORGEJO_URL:-http://192.168.27.9:3000}
       volumes:
         - /volume1/docker/forgejo/runner:/data
         - /var/run/docker.sock:/var/run/docker.sock
       command:
         - /bin/sh
         - -ec
         - |
           cd /data
           if [ ! -f .runner ]; then
             forgejo-runner register --no-interactive --instance "$$FORGEJO_URL" \
               --token "$$RUNNER_TOKEN" --name picocalc-builder \
               --labels docker:docker://node:20-bookworm
           fi
           if [ ! -f config.yml ]; then
             forgejo-runner generate-config > config.yml
             sed -i '/^cache:/,/^container:/ s/^  enabled: true/  enabled: false/' config.yml
           fi
           exec forgejo-runner -c config.yml daemon
   ```

   On first start the script registers the runner, which writes `.runner`
   into the data directory, generates `config.yml` with the actions cache
   switched off (the workflow does not use it, and the cache server inside
   the runner container is not reachable from job containers without extra
   network setup), then runs the daemon. Later starts find both files and
   go straight to the daemon. The label name `docker` is what
   `runs-on: docker` in the workflow matches; its default image only
   applies to jobs that do not name one.

   Group membership only helps while the socket is group-writable. Check
   it with `stat -c %A /var/run/docker.sock`: `srw-rw----` is fine. If it
   shows `srw-------`, drop `group_add` and use `user: "0:0"` instead, at
   the cost of root-owned files in the data directory.

3. In the stack's environment variables add `RUNNER_TOKEN` with the token
   from step 1. `FORGEJO_URL` only needs setting if the LAN address is
   wrong for the runner; the Forgejo service name inside the compose
   network, such as `http://forgejo:3000`, works too.

4. Update the stack. Until the runner can reach Forgejo with a valid
   token the container keeps retrying and nothing appears in the data
   directory; its log in Portainer shows why. Once it is registered the
   runner page from step 1 lists it as online, and `RUNNER_TOKEN` can be
   removed from the stack.

To register again later, for example after moving the runner or revoking
it in Forgejo, delete `.runner` from the data directory, set a fresh
`RUNNER_TOKEN` and update the stack. For anything else interactive,
Portainer's container console (Containers, the runner, Console, with
`1026` as the user) opens a shell in the running container.

Job containers talk to Forgejo through the server's ROOT_URL
(`http://192.168.27.9:3000`), which Forgejo passes to every job, so the
host's published port is all they need.

## Cutting a release

The tag's commit must contain the workflow file, so push `main` first.

```sh
git push origin main
git tag v0.1.0
git push origin v0.1.0
```

The tag is the only place the version lives. `version.cmake` embeds the
output of `git describe` in the boot banner and `sys.version`, `build.sh`
uses it as the UF2 suffix when no version is given, and
`make-sd-archive.sh` writes it to the archive's `version.txt`, so bumping
the version is just choosing the next `vX.Y.Z` tag.

The run appears under the repository's Actions tab. When it finishes, the
Releases page lists a draft `v0.1.0` with the five UF2 files,
`sd_files-v0.1.0.tar.gz` and `SHA256SUMS.txt`. Edit the notes if needed and
publish. To rebuild the same tag, delete the draft first: the workflow
refuses to create a second release for a tag.

To stage an existing tag without pushing again, open Actions, pick
"Release", choose "Run workflow" and enter the tag; the pre-release box
marks the draft as a pre-release.

On a PicoCalc the published archive installs the same way as a local one:

```
fetch http://192.168.27.9:3000/steve/picocalc_lua/releases/download/v0.1.0/sd_files-v0.1.0.tar.gz /sd_files.tar.gz
tar x /sd_files.tar.gz
```

`lua/wifi.conf` and the per-device configs are excluded by
`make-sd-archive.sh`, exactly as for a locally built archive.

## Development builds

Between releases the device can pull a local build directly. `build.sh`
and `make-sd-archive.sh` name their output after `git describe`, so serve
the deploy directory and give the device that string:

```sh
./build.sh pico2w && ./make-sd-archive.sh
python3 -m http.server 8080 -d /home/steve/dev/picocalc/uf2-deploy
```

On the PicoCalc, `fetch-dev v0.6.0-3-g1729db7` downloads the firmware
for its own board into the uf2-loader directory and the archive into the
SD root, then prints the install steps. The server defaults to
`http://192.168.27.164:8080`; a second argument overrides it.

## Job image

The image is built on the NAS Docker host, where the runner's jobs run,
with `ci/builder/build-image.sh <sdk-version>` from the picocalc-z80
repository. Rerun it now and then to pick up Ubuntu updates. After a Pico
SDK upgrade run it with the new version and change `container.image` in
the workflow to match; a job that names a tag which has not been built
fails before its first step.
