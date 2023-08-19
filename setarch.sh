#!/bin/sh
architecture=""
    case $(uname -m) in
        x86_64) architecture="amd64" ;;
        arm*)    apk --print-arch | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
    esac

echo $architecture > /tmp/arch
