#!/bin/bash
# CDDL HEADER START
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#
# CDDL HEADER END

# Copyright 2022 Saso Kiselkov. All rights reserved.

while getopts "a:g:hnt:" opt; do
	case $opt in
	a)
		LIBACFUTILS="$OPTARG"
		;;
	g)
		OPENGPWS="$OPTARG"
		;;
	h)
		cat << EOF
Usage: $0 [-nh] -a <libacfutils> -g <opengpws> [-t <buildtype>]
    -h : shows the current help screen
    -a <libacfutils> : the path to the built libacfutils repo
    -g <opengpws> : the path to the OpenGPWS repo (only used for headers)
    -n : (macOS-only) codesign and notarize the resulting binary
	Notarization requires an Apple Developer account. Access credentials
	should be stored in your Keychain and the appropriate account name
	references should be placed into a custom file you will create under
	notarize/user.make with the following two lines:
		DEVELOPER_USERNAME := "apple_ID@whatever.com"
		DEVELOPER_PASSWORD := "@keychain:<ALTOOL_KEYCHAIN_ENTRY_NAME>"
	These will be passed to the notarization tool (altool) to authenticate
	the notarization request to Apple.
    -t <buildtype> : specifies which type of plugin to build. The options are:
	-t standalone : this is the default, and builds with:
	    BACKEND=0 : libradio won't just operate as a radio backend
	    APCTL=1 : libradio will control default X-Plane autopilot datarefs
	    OPENGPWS_CTL=1 : libradio will take charge of controlling OpenGPWS
	    DEF_CLAMP=1 : radio deflection datarefs will be clamped
	-t felis742 : these are the settings for the Felis 742:
	    BACKEND=0 : libradio won't just operate as a radio backend
	    APCTL=0 : libradio will NOT control default X-Plane autopilot
	    OPENGPWS_CTL=1 : libradio will take charge of controlling OpenGPWS
	    DEF_CLAMP=1 : radio deflection datarefs will NOT be clamped
EOF
		exit
		;;
	n)
		if [[ "$(uname)" != Darwin ]]; then
			echo "Notarization can only be performed on macOS" >&2
			exit 1
		fi
		NOTARIZE=1
		;;
	t)
		BUILDTYPE="$OPTARG"
		;;
	*)
		"Unknown argument $opt. Try $0 -h for help." >&2
		exit 1
		;;
	esac
done

if [ -z "$BUILDTYPE" ]; then
	BUILDTYPE=standalone
fi

case "$BUILDTYPE" in
standalone)
	CMAKE_OPTS="-DBACKEND=0 -DAPCTL=1 -DOPENGPWS_CTL=1 -DDEF_CLAMP=1"
	;;
felis742)
	CMAKE_OPTS="-DBACKEND=0 -DAPCTL=0 -DOPENGPWS_CTL=1 -DDEF_CLAMP=0"
	;;
*)
	echo "Unknown options value $OPTIONS. See $0 -h for help" >&2
	exit 1
	;;
esac

if [ -z "$LIBACFUTILS" ]; then
	echo "Missing -a argument. Try $0 -h for help" >&2
	exit 1
fi

if [ -z "$OPENGPWS" ]; then
	echo "Missing -g argument. Try $0 -h for help" >&2
	exit 1
fi

set -e

case "$(uname)" in
Darwin)
	NCPUS=$(( $(sysctl -n hw.ncpu) + 1 ))
	if ! [ -f libradio.plugin/mac_x64/libradio.plugin.xpl ]; then
		rm -f CMakeCache.txt
		cmake . -DOPENGPWS="$OPENGPWS" -DLIBACFUTILS="$LIBACFUTILS" \
		    $CMAKE_OPTS
		cmake --build . --parallel "$NCPUS"
		if [ -n "$NOTARIZE" ]; then
			make -f notarize/notarize.make notarize
		fi
	fi
	;;
Linux)
	NCPUS=$(( $(grep 'processor[[:space:]]\+:' /proc/cpuinfo  | wc -l) + \
	    1 ))
	if ! [ -f libradio.plugin/lin_x64/libradio.plugin.xpl ]; then
		rm -f CMakeCache.txt
		cmake . -DOPENGPWS="$OPENGPWS" -DLIBACFUTILS="$LIBACFUTILS" \
		    $CMAKE_OPTS
		cmake --build . --parallel "$NCPUS"
	fi
	if ! [ -f libradio.plugin/win_x64/libradio.plugin.xpl ]; then
		rm -f CMakeCache.txt
		cmake . -DOPENGPWS="$OPENGPWS" -DLIBACFUTILS="$LIBACFUTILS" \
		    -DCMAKE_TOOLCHAIN_FILE=XCompile.cmake \
		    -DHOST=x86_64-w64-mingw32 \
		    $CMAKE_OPTS
		cmake --build . --parallel "$NCPUS"
		rm -f liblibradio.plugin.xpl.dll.a
	fi
	;;
*)
	echo "Unsupported build platform" >&2
	exit 1
	;;
esac
