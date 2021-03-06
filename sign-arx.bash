#!/bin/bash
set -o nounset -o errexit -o pipefail
function usage {
cat <<USAGE
 USAGE: signed-arx.bash mk <platform tag>?
 USAGE: signed-arx.bash sign_and_sum <file> <platform> <version>

  In the first form, automatically determines GHC target architecture and
  platform tag and builds and signs arx. You may specify the platform tag if,
  for example, you want to indicate that the binary is only intended for
  Leopard or Ubuntu.

  In the second form, simply signs and archives the given file (for example,
  /tmp/arx) with version and platform as specified. Used to sign a binary on a
  machine other than the one it was built on (for example).

USAGE
};function -h { usage ;};function --help { usage ;};function help { usage ;}

declare -a sedRE
if sed --version &>/dev/null
then
  sedRE=(sed -r)
else
  sedRE=(sed -E)
fi

d=./tmp/signed

function sedRE {
  "${sedRE[@]}" "$@"
}

function version {
  sedRE -n '/^version *: *([^ ]+)$/ { s//\1/ ; p ;}' ./arx.cabal
}

function ghc_target {
  ghc --info |
  sedRE -n '/^.+"Target platform","([^-]+)-([^"]+)".+$/ { s//\1 \2/ ; p ;}' |
  sedRE 's/x86_64/amd64/'
}

function mk_arx {
  local target=''
  { { uname -a | fgrep -q Ubuntu ;} && target=./tmp/arx.ubuntu ;} ||
  { { uname -a | fgrep -q Darwin ;} && target=./tmp/arx.osx ;} ||
  { echo 'Unknown target...' >&2 ; exit 4 ;}
  if ! make "$target" >&/dev/null
  then
    echo 'Build error!' >&2
    exit 4
  fi
  mv "$target" ./tmp/arx
}

function sign_and_sum {
  local file="$1"
  local name="$(basename "$file")"
  local platform="$2"
  local version="$3"
  local v="$(basename "$file")"-"$version"-"$platform"
  mkdir -p "$d/$v"
  echo "Copying binary to $d/$v/$name" >&2
  rsync -qa "$file" "$d/$v/$name"
  echo "Creating GPG signature file, $d/$v/$name.sig" >&2
  rm -f "$d/$v/$name".sig
  gpg --use-agent --detach-sign "$d/$v/$name"
  echo "Creating SHA 512 sum, $d/$v/$name.sha" >&2
  ( cd "$d/$v" &&
    shasum --portable --algorithm 512 "$name" > ./"$name.sha" )
  echo "Creating archive, $d/$v.tbz" >&2
  ( cd "$d" && tar cjf "$v".tbz "$v" )
}

function mk {
  local sign_args=('./tmp/arx')
  while [[ $# != 0 ]]
  do
    case "$1" in
      *) case "${#sign_args[@]}" in
           1) sign_args[1]="$1" ;;
           *) echo 'Bad arguments.' >&2 ; exit 2 ;;
         esac ;;
    esac
    shift
  done
  local target=( $(ghc_target) )
  case "${#sign_args[@]}" in
    1) sign_args[1]="${target[0]}"-"${target[1]}" ;;
    2) sign_args[1]="${target[0]}"-"${sign_args[1]}" ;;
    *) echo 'Bad arguments.' >&2 ; exit 2 ;;
  esac
  echo 'Building stripped binary...' >&2
  mk_arx
  sign_and_sum "${sign_args[@]}" "$(version)"
}

"$@"

