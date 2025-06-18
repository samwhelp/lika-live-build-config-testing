#!/usr/bin/env bash

##
## > If a command fails, make the whole script exit
##
set -e

##
## > Use return code for any command errors in part of a pipe
##
set -o pipefail # Bashism

##
## ## Default Values
##
MASTER_NAME="lika"
MASTER_DIST="bookworm"
MASTER_VERSION=""
MASTER_VARIANT="default"
IMAGE_TYPE="live"
TARGET_DIR="$(dirname ${0})/images"
TARGET_SUBDIR=""
SUDO="sudo"
VERBOSE=""
DEBUG=""
HOST_ARCH=$(dpkg --print-architecture)

image_name () {
	case "${IMAGE_TYPE}" in
		live)
			live_image_name
		;;
		installer)
			installer_image_name
		;;
	esac
}

live_image_name () {
	case "${MASTER_ARCH}" in
		i386|amd64|arm64)
			echo "live-image-${MASTER_ARCH}.hybrid.iso"
		;;
		armel|armhf)
			echo "live-image-${MASTER_ARCH}.img"
		;;
	esac
}

installer_image_name () {
	if [ "${MASTER_VARIANT}" = "netinst" ]; then
		echo "simple-cdd/images/lika-${MASTER_VERSION}-${MASTER_ARCH}-NETINST-1.iso"
	else
		echo "simple-cdd/images/lika-${MASTER_VERSION}-${MASTER_ARCH}-BD-1.iso"
	fi
}

target_image_name () {
	local arch=${1}

	IMAGE_NAME="$(image_name $arch)"
	IMAGE_EXT="${IMAGE_NAME##*.}"
	if [ "${IMAGE_EXT}" = "${IMAGE_NAME}" ]; then
		IMAGE_EXT="img"
	fi
	if [ "${IMAGE_TYPE}" = "live" ]; then
		if [ "${MASTER_VARIANT}" = "default" ]; then
			echo "${TARGET_SUBDIR:+${TARGET_SUBDIR}/}${MASTER_NAME}-linux-${MASTER_VERSION}-live-${MASTER_ARCH}.${IMAGE_EXT}"
		else
			echo "${TARGET_SUBDIR:+${TARGET_SUBDIR}/}${MASTER_NAME}-linux-${MASTER_VERSION}-live-${MASTER_VARIANT}-${MASTER_ARCH}.${IMAGE_EXT}"
		fi
	else
		if [ "${MASTER_VARIANT}" = "default" ]; then
			echo "${TARGET_SUBDIR:+${TARGET_SUBDIR}/}${MASTER_NAME}-linux-${MASTER_VERSION}-installer-${MASTER_ARCH}.${IMAGE_EXT}"
		else
			echo "${TARGET_SUBDIR:+${TARGET_SUBDIR}/}${MASTER_NAME}-linux-${MASTER_VERSION}-installer-${MASTER_VARIANT}-${MASTER_ARCH}.${IMAGE_EXT}"
		fi
	fi
}

target_build_log () {
	TARGET_IMAGE_NAME=$(target_image_name ${1})
	echo ${TARGET_IMAGE_NAME%.*}.log
}

default_version () {
	case "${1}" in
		lika-*)
			echo "${1#lika-}"
		;;
		*)
			echo "${1}"
		;;
	esac
}

failure () {
	echo "Build of ${MASTER_DIST}/${MASTER_VARIANT}/${MASTER_ARCH} ${IMAGE_TYPE} image failed (see build.log for details)" >&2
	echo "Log: ${BUILD_LOG}" >&2
	exit 2
}

run_and_log () {
	if [ -n "${VERBOSE}" ] || [ -n "${DEBUG}" ]; then
		printf "RUNNING:" >&2
		for _ in "$@"; do
			[[ $_ =~ [[:space:]] ]] && printf " '%s'" "$_" || printf " %s" "$_"
		done >&2
		printf "\n" >&2
		"$@" 2>&1 | tee -a "${BUILD_LOG}"
	else
		"$@" >>"${BUILD_LOG}" 2>&1
	fi
	return ${?}
}

debug () {
	if [ -n "${DEBUG}" ]; then
		echo "DEBUG: $*" >&2
	fi
}

clean () {
	debug "Cleaning"

	# Live
	run_and_log ${SUDO} lb clean --purge
	#run_and_log ${SUDO} umount -l $(pwd)/chroot/proc
	#run_and_log ${SUDO} umount -l $(pwd)/chroot/dev/pts
	#run_and_log ${SUDO} umount -l $(pwd)/chroot/sys
	#run_and_log ${SUDO} rm -rf $(pwd)/chroot
	#run_and_log ${SUDO} rm -rf $(pwd)/binary

	# Installer
	run_and_log ${SUDO} rm -rf "$(pwd)/simple-cdd/tmp"
	run_and_log ${SUDO} rm -rf "$(pwd)/simple-cdd/debian-cd"
}

print_help () {
	echo "Usage: ${0} [<option>...]"
	echo
	for x in $(echo "${BUILD_OPTS_LONG}" | sed 's_,_ _g'); do
		x=$(echo $x | sed 's/:$/ <arg>/')
		echo "  --${x}"
	done
	echo
	echo "More information: https://samwhelp.github.io/note-about-lika/"
	exit 0
}

require_package () {
	local pkg=${1}
	local required_version=${2}
	local pkg_version=""

	pkg_version=$(dpkg-query -f '${Version}' -W ${pkg} || true)
	if [ -z "${pkg_version}" ]; then
		echo "ERROR: You need ${pkg}, but it is not installed" >&2
		exit 1
	fi
	if dpkg --compare-versions "${pkg_version}" lt "${required_version}"; then
		echo "ERROR: You need ${pkg} (>= ${required_version}), you have ${pkg_version}" >&2
		exit 1
	fi
	debug "${pkg} version: ${pkg_version}"
}

##
## > Allowed command line options
##
. $(dirname ${0})/.getopt.sh

BUILD_LOG="$(pwd)/build.log"
debug "BUILD_LOG: ${BUILD_LOG}"
# Create empty file
: > "${BUILD_LOG}"

##
## > Parsing command line options (see .getopt.sh)
##
temp=$(getopt -o "${BUILD_OPTS_SHORT}" -l "${BUILD_OPTS_LONG},get-image-path" -- "$@")
eval set -- "${temp}"
while true; do
	case "${1}" in
		-d|--distribution) MASTER_DIST="${2}"; shift 2; ;;
		-p|--proposed-updates) OPT_pu="1"; shift 1; ;;
		-a|--arch) MASTER_ARCH="${2}"; shift 2; ;;
		-v|--verbose) VERBOSE="1"; shift 1; ;;
		-D|--debug) DEBUG="1"; shift 1; ;;
		-s|--salt) shift; ;;
		-h|--help) print_help; ;;
		--installer) IMAGE_TYPE="installer"; shift 1 ;;
		--live) IMAGE_TYPE="live"; shift 1 ;;
		--variant) MASTER_VARIANT="${2}"; shift 2; ;;
		--version) MASTER_VERSION="${2}"; shift 2; ;;
		--subdir) TARGET_SUBDIR="${2}"; shift 2; ;;
		--get-image-path) ACTION="get-image-path"; shift 1; ;;
		--clean) ACTION="clean"; shift 1; ;;
		--no-clean) NO_CLEAN="1"; shift 1 ;;
		--) shift; break; ;;
		*) echo "ERROR: Invalid command-line option: ${1}" >&2; exit 1; ;;
	esac
done

##
## > Set default values
##
MASTER_ARCH=${MASTER_ARCH:-$HOST_ARCH}
if [ "${MASTER_ARCH}" = "x64" ]; then
	MASTER_ARCH="amd64"
elif [ "${MASTER_ARCH}" = "x86" ]; then
	MASTER_ARCH="i386"
fi
debug "MASTER_ARCH: ${MASTER_ARCH}"

if [ -z "${MASTER_VERSION}" ]; then
	MASTER_VERSION="$(default_version ${MASTER_DIST})"
fi
debug "MASTER_VERSION: ${MASTER_VERSION}"

##
## > Check parameters
##
debug "HOST_ARCH: ${HOST_ARCH}"
if [ "${HOST_ARCH}" != "${MASTER_ARCH}" ] && [ "${IMAGE_TYPE}" != "installer" ]; then
	case "${HOST_ARCH}/${MASTER_ARCH}" in
		amd64/i386|i386/amd64)
		;;
		*)
			echo "Can't build ${MASTER_ARCH} image on ${HOST_ARCH} system." >&2
			exit 1
		;;
	esac
fi

##
## > Build parameters for lb config
##
MASTER_CONFIG_OPTS="--distribution ${MASTER_DIST} -- --variant ${MASTER_VARIANT}"
CODENAME=${MASTER_DIST} # for simple-cdd/debian-cd
if [ -n "${OPT_pu}" ]; then
	MASTER_CONFIG_OPTS="${MASTER_CONFIG_OPTS} --proposed-updates"
	MASTER_DIST="${MASTER_DIST}+pu"
fi
debug "MASTER_CONFIG_OPTS: ${MASTER_CONFIG_OPTS}"
debug "CODENAME: ${CODENAME}"
debug "MASTER_DIST: ${MASTER_DIST}"

##
## > Set sane PATH (cron seems to lack /sbin/ dirs)
##
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
debug "PATH: $PATH"

if grep -q -e "^ID=debian" -e "^ID_LIKE=debian" /usr/lib/os-release; then
	debug "OS: $( . /usr/lib/os-release && echo ${NAME} ${VERSION} )"
elif [ -e /etc/debian_version ]; then
	debug "OS: $( cat /etc/debian_version )"
else
	echo "ERROR: Non Debian-based OS" >&2
fi

debug "IMAGE_TYPE: ${IMAGE_TYPE}"
case "${IMAGE_TYPE}" in
	live)
		if [ ! -d "$(dirname ${0})/master-config/variant-${MASTER_VARIANT}" ]; then
			echo "ERROR: Unknown variant of Lika live configuration: ${MASTER_VARIANT}" >&2
			exit 1
		fi
		require_package live-build "1:20230502"
		require_package debootstrap "1.0.97"
	;;
	installer)
		## TODO:
		echo "TODO: Unsupported IMAGE_TYPE=installer now."
		exit 1
		if [ ! -d "$(dirname ${0})/master-config/installer-${MASTER_VARIANT}" ]; then
			echo "ERROR: Unknown variant of Lika installer configuration: ${MASTER_VARIANT}" >&2
			exit 1
		fi
		require_package debian-cd "3.2.1"
		require_package simple-cdd "0.6.9"
	;;
	*)
		echo "ERROR: Unsupported IMAGE_TYPE selected (${IMAGE_TYPE})" >&2
		exit 1
	;;
esac

##
## > We need root rights at some point
##
if [ "$(whoami)" != "root" ]; then
	if ! which ${SUDO} >/dev/null; then
		echo "ERROR: ${0} is not run as root and ${SUDO} is not available" >&2
		exit 1
	fi
else
	SUDO="" # We're already root
fi
debug "SUDO: ${SUDO}"

IMAGE_NAME="$(image_name ${MASTER_ARCH})"
debug "IMAGE_NAME: ${IMAGE_NAME}"

debug "ACTION: ${ACTION}"
if [ "${ACTION}" = "get-image-path" ]; then
	echo $(target_image_name ${MASTER_ARCH})
	exit 0
fi

if [ "${NO_CLEAN}" = "" ]; then
	clean
fi
if [ "${ACTION}" = "clean" ]; then
	exit 0
fi

cd $(dirname ${0})
mkdir -p ${TARGET_DIR}/${TARGET_SUBDIR}

##
## > Don't quit on any errors now
##
set +e

case "${IMAGE_TYPE}" in
	live)
		debug "Stage 1/2 - Config"
		run_and_log lb config -a ${MASTER_ARCH} ${MASTER_CONFIG_OPTS} "$@"
		[ ${?} -eq 0 ] || failure

		debug "Stage 2/2 - Build"
		run_and_log ${SUDO} lb build
		if [ ${?} -ne 0 ] || [ ! -e ${IMAGE_NAME} ]; then
			failure
		fi
	;;
	installer)
		##
		## > Override some debian-cd environment variables
		##
		export BASEDIR="$(pwd)/simple-cdd/debian-cd"
		export ARCHES=${MASTER_ARCH}
		export ARCH=${MASTER_ARCH}
		export DEBVERSION=${MASTER_VERSION}
		debug "BASEDIR: ${BASEDIR}"
		debug "ARCHES: ${ARCHES}"
		debug "ARCH: ${ARCH}"
		debug "DEBVERSION: ${DEBVERSION}"

		if [ "${MASTER_VARIANT}" = "netinst" ]; then
			export DISKTYPE="NETINST"
			profiles="lika"
			auto_profiles="lika"
		elif [ "${MASTER_VARIANT}" = "purple" ]; then
			export DISKTYPE="BD"
			profiles="lika lika-purple offline"
			auto_profiles="lika lika-purple offline"
			export KERNEL_PARAMS="debian-installer/theme=Clearlooks-Purple"
		else    # plain installer
			export DISKTYPE="BD"
			profiles="lika offline"
			auto_profiles="lika offline"
		fi
		debug "DISKTYPE: ${DISKTYPE}"
		debug "profiles: ${profiles}"
		debug "auto_profiles: ${auto_profiles}"
		[ -v KERNEL_PARAMS ] && debug "KERNEL_PARAMS: ${KERNEL_PARAMS}"

		if [ -e .mirror ]; then
			master_mirror=$(cat .mirror)
		else
			master_mirror="http://deb.debian.org/debian"
		fi
		if ! echo "${master_mirror}" | grep -q '/$'; then
			master_mirror="${master_mirror}/"
		fi
		debug "master_mirror: ${master_mirror}"

		debug "Stage 1/2 - File(s)"
		##
		## > Setup custom debian-cd to make our changes
		##
		cp -aT /usr/share/debian-cd simple-cdd/debian-cd
		[ ${?} -eq 0 ] || failure

		##
		## > Use the same grub theme as in the live images
		## > Until debian-cd is smart enough: http://bugs.debian.org/1003927
		##
		cp -f master-config/common/bootloaders/grub-pc/grub-theme.in simple-cdd/debian-cd/data/${CODENAME}/grub-theme.in

		##
		## > Keep 686-pae udebs as we changed the default from 686
		## > to 686-pae in the debian-installer images
		##
		sed -i -e '/686-pae/d' \
			simple-cdd/debian-cd/data/${CODENAME}/exclude-udebs-i386
		[ ${?} -eq 0 ] || failure

		##
		## > Configure the lika profile with the packages we want
		##
		grep -v '^#' master-config/installer-${MASTER_VARIANT}/packages \
			> simple-cdd/profiles/lika.downloads
		[ ${?} -eq 0 ] || failure

		##
		## > Tasksel is required in the mirror for debian-cd
		##
		echo tasksel >> simple-cdd/profiles/lika.downloads
		[ ${?} -eq 0 ] || failure

		##
		## > Grub is the only supported bootloader on arm64
		## > so ensure it's on the iso for arm64.
		if [ "${MASTER_ARCH}" = "arm64" ]; then
			debug "arm64 GRUB"
			echo "grub-efi-arm64" >> simple-cdd/profiles/lika.downloads
			[ ${?} -eq 0 ] || failure
		fi

		##
		## > Run simple-cdd
		##
		debug "Stage 2/2 - Build"
		cd simple-cdd/
		run_and_log build-simple-cdd \
			--verbose \
			--debug \
			--force-root \
			--conf simple-cdd.conf \
			--dist ${CODENAME} \
			--debian-mirror ${master_mirror} \
			--profiles "${profiles}" \
			--auto-profiles "${auto_profiles}"
		res=${?}
		cd ../
		if [ ${res} -ne 0 ] || [ ! -e ${IMAGE_NAME} ]; then
			failure
		fi
	;;
esac

##
## > If a command fails, make the whole script exit
##
set -e

debug "Moving files"
run_and_log mv -f ${IMAGE_NAME} ${TARGET_DIR}/$(target_image_name ${MASTER_ARCH})
run_and_log mv -f "${BUILD_LOG}" ${TARGET_DIR}/$(target_build_log ${MASTER_ARCH})

run_and_log echo -e "\n***\nGENERATED FINAL IMAGE: ${TARGET_DIR}/$(target_image_name ${MASTER_ARCH})\n***"
