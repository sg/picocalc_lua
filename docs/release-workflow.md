# Release workflow

`.github/workflows/release.yml` turns a tag into a staged release. When a
tag matching `v*` is pushed (or the workflow is started by hand for an
existing tag) a job builds `picolua-<board>-<tag>.uf2` for all five boards
with `build.sh`, packs the SD-card files with `make-sd-archive.sh`, writes
`SHA256SUMS.txt`, and creates a **draft** release with those assets and the
commit list since the previous tag as notes. Nothing is public until the
draft is reviewed and published on GitHub.

`.github/workflows/build.yml` runs the same five builds for every push to
`main` and every pull request and keeps the UF2s as the run's artifacts,
so a broken build shows up before a tag is cut.

Both jobs run on GitHub's `ubuntu-24.04` runners and share the composite
action in `.github/actions/pico-toolchain`: Ubuntu's `gcc-arm-none-eabi`
13.2, the same package as the development machine, plus a Pico SDK clone
and a picotool build at the version the action's `sdk-version` input
names. The SDK and picotool are cached per version, so the first run
after an SDK bump spends a few minutes on them and later runs restore them
in seconds. Bumping the SDK means changing that default alongside
`sdkVersion` in `CMakeLists.txt`.

## Cutting a release

Push `main` first so the workflow file is on GitHub, then tag:

```sh
git push origin main
git tag -a v0.1.0 -m "Release v0.1.0"
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
marks the draft as a pre-release. From a terminal:

```sh
gh workflow run release.yml -R sg/picocalc_lua -f tag=v0.1.0
```

On a PicoCalc the `update` command installs a published release. The
archive can also be fetched by hand:

```
fetch https://github.com/sg/picocalc_lua/releases/download/v0.1.0/sd_files-v0.1.0.tar.gz /sd_files.tar.gz
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
