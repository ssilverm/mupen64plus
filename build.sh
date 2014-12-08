#!/bin/bash

# terminate the script if any commands return a non-zero error code
set -e

if [ "$1" = "-h" -o "$1" = "--help" ]; then
	echo "Mupen64plus installer for the Raspberry PI"
	echo "Usage:"
	echo "[Environment Vars] ./buid_test.sh [makefile targets]"
	echo
	echo "Environment Variable options:"
	echo ""
	echo "    CLEAN=[1]                    Clean before build"
	echo "    DEBUG=[0]                    Compile for Debugging"
	echo "    DEV=[0]                      Development build - installs into ./test"
	echo "    GCC=[4.7]                    Version of gcc to use"
	echo "    MAKE=[make]                  Make Utility to use"
	echo "    MAKE_SDL2=[0]                Force building of SDL2 library"
	echo "    M64P_COMPONENTS=             The list of components to download and build"
	echo "                                 The default is to read ./pluginList. "
	echo "                                 One can specify the plugin names e.g. 'core'."
	echo "                                 This will override automatic changing of the branch"
	echo "    PLUGIN_FILE=[defaultList]    File with List of plugins to build"
	echo "    BUILDDIR=[./] | PREFIX=[./]  Directory to download and build plugins in"
	echo "    REPO=[mupen64plus]           Default repository on https://github.com"

	echo ""

	exit 0
fi

#-------------- User Configurable --------------------------------------------------

#the file to read the git repository list from
defaultPluginList="defaultList"
MEM_REQ=750			# The number of M bytes of memory required to build
USE_SDL2=1			# Use SDL2?
SDL2="SDL2-2.0.3"		# SDL Library version
SDL_CFG="--disable-video-opengl --disable-video-x11"

#------------ Defaults -----------------------------------------------------------

if [ -z "$GCC" ]; then
GCC=4.7
fi

if [ -z "$MAKE_SDL2" ]; then
MAKE_SDL2="0"
fi

if [ -z "$COREDIR" ]; then
COREDIR="/usr/local/lib/"
fi

if [ -z "$MAKE_SDL2" ]; then
MAKE_SDL2="0"
fi

if [ -z "$DEV" ]; then
DEV="0"
fi

if [ -z "$CLEAN" ]; then
CLEAN="1"
fi

IAM=`whoami`
M64P_COMPONENTS_FILE=0
GPU=0
MAKE_INSTALL="PLUGINDIR= SHAREDIR= BINDIR= MANDIR= LIBDIR= INCDIR=api LDCONFIG=true"
PATH=$PWD:$PATH			# Add the current directory to $PATH so we can override gcc/g++ version

#-------------------------------------------------------------------------------

DO_UPDATE=1
apt_update()
{
	if [ "$DO_UPDATE" = "1" ] && [ "$IAM" = "root" ]; then
		apt-get update
	fi
	DO_UPDATE="0"
}

#------------------- set some variables ----------------------------------------

if [ -n "$PREFIX" ]; then
	BUILDDIR="$PREFIX"
fi

if [ -z "$MAKE" ]; then
	MAKE=make
fi

if [ -z "${M64P_COMPONENTS}" ]; then
	if [ -n "${PLUGIN_FILE}" ]; then
		defaultPluginList="${PLUGIN_FILE}"
	fi

	M64P_COMPONENTS_FILE=1

	#get file contents, ignore comments, blank lines and replace multiple tabs with single comma
	M64P_COMPONENTS=`cat "${defaultPluginList}" | grep -v -e '^#' -e '^$' | cut -d '#' -f 1 | sed -r 's:\t+:,:g'`
fi

if [ -z "${BUILDDIR}" ]; then
	BUILDDIR="."
fi

if [ ! -d "${BUILDDIR}" ]; then
	mkdir "${BUILDDIR}"
fi

if [ -z "${REPO}" ]; then
	REPO="mupen64plus"
fi

#------------------------------- Raspberry PI firmware -----------------------------------

if [ 0 -eq 1 ]; then
	if [ ! -d "/opt/vc" ]; then
		git clone --depth 1 "https://github.com/raspberrypi/firmware"
		if [ "$IAM" = "root" ]; then
			cp -R -f "${BUILDDIR}/firmware/opt/vc" "/opt"
		else
			echo "You need to run this script with sudo/root or copy the Videocore firmware drivers using 'sudo cp -R -f \"${BUILDDIR}/firmware/opt/vc\" /opt'"
			exit 1
		fi
	fi
fi

#------------------------------- GCC compiler --------------------------------------------


if [ "$IAM" = "root" ]; then
	if [ ! -e "/usr/bin/gcc-$GCC" ]; then
		echo "************************************ Downloading/Installing GCC $GCC"
		apt_update
		apt-get install gcc-$GCC
	fi
	if [ ! -e "/usr/bin/g++-$GCC" ]; then
		echo "************************************ Downloading/Installing G++ $GCC"
		apt_update
		apt-get install g++-$GCC
	fi
else
	if [ ! -e "/usr/bin/gcc-$GCC" ]; then
		echo "You should install the GCC $GCC compiler"
		echo "Either run this script with sudo/root or run 'apt-get install gcc-$GCC'"
		exit 1
	fi
	if [ ! -e "/usr/bin/g++-$GCC" ]; then
		echo "You should install the G++ $GCC compiler"
		echo "Either run this script with sudo/root or run 'apt-get install g++-$GCC'"
		exit 1
	fi
fi

if [ -e "/usr/bin/gcc-$GCC" ]; then
	ln -f -s /usr/bin/gcc-$GCC gcc
fi

if [ -e "/usr/bin/g++-$GCC" ]; then
	ln -f -s /usr/bin/g++-$GCC g++
fi

#------------------------------- SDL dev libraries --------------------------------------------

if [ "$USE_SDL2" = "1" ]; then

	if [ "$MAKE_SDL2" = "1" ] || [ ! -e "/usr/local/lib/libSDL2.so" ]; then
		echo "************************************ Downloading SDL2"

		pushd "${BUILDDIR}"

		if [ ! -e "${BUILDDIR}/${SDL2}" ]; then
			wget http://www.libsdl.org/release/$SDL2.tar.gz
			tar -zxf $SDL2.tar.gz
		fi
		popd
	fi

	pushd ${BUILDDIR}/${SDL2}

SDL_OLD_CFG=""

	if [ -e "config.log" ]; then
		SDL_OLD_CFG=`head config.log | grep  "\./configure" | cut -d " " -f 5-`
	fi

	if [ "$SDL_OLD_CFG" != "$SDL_CFG" ]; then
		echo "************************************ Configuring/Build/Install SDL2"
		echo "./configure $SDL_CFG"

		./configure $SDL_CFG
		make

		if [ "$IAM" = "root" ]; then
			make install
		else
			echo "You need to install SDL2 development libraries"
			echo "Either run this script with sudo/root or run 'pushd ${BUILDDIR}/$SDL2; sudo make install; popd'"
			exit 1
		fi
	fi
	
	popd

	# Override mupen64-core Makefile SDL
	SDL_CFLAGS=`sdl2-config --cflags`
  	SDL_LDLIBS=`sdl2-config --libs`
else
	if [ "$IAM" = "root" ]; then
		if [ ! -e "/usr/bin/sdl-config" ]; then
			echo "************************************ Downloading/Installing SDL"
			apt_update
			apt-get install -y libsdl1.2-dev
		fi
	else
		if [ ! -e "/usr/bin/sdl-config" ]; then
			echo "You need to install SDL development libraries"
			echo "Either run this script with sudo/root or run 'sudo apt-get install libsdl1.2-dev'"
			exit 1
		fi
	fi
  	SDL_CFLAGS=`sdl-config --cflags`
  	SDL_LDLIBS=`sdl-config --libs`
fi

#------------------------------- Setup Information to debug problems --------------------------------

if [ 1 -eq 1 ]; then
	echo ""
	echo "--------------- Setup Information -------------"
	git --version
	free -h
	gcc -v 2>&1 | tail -n 1
#	g++ -v 2>&1 | tail -n 1
	GCC=`gcc -v 2>&1 | tail -n 1 | cut -d " " -f 3`

	RESULT=`git log -n 1 | head -n 1`
	echo "Build script: $RESULT"

	echo "DEV: $DEV"

	#Check what is being built"
	RESULT=`git diff --name-only defaultList | wc -l`
	if [ "$RESULT" = "1" ] || [ -n "$PLUGIN_LIST" ]; then
		echo "Using Modifed List"
#		echo "--------------------------"
#		cat "$defaultPluginList"
#		echo "--------------------------"
	else
		echo "Using DefaultList"
	fi

	if [ "$USE_SDL2" = "1" ] && [ -e "/usr/local/bin/sdl2-config" ]; then
		echo "Using SDL 2"
	else
		if [ -e "/usr/bin/sdl-config" ]; then
			echo "Using SDL1.2"
		else
			echo "Unknown SDL setup"
		fi
	fi

	if [ -e "/boot/config.txt" ]; then
		cat /boot/config.txt | grep "gpu_mem"
		GPU=`cat /boot/config.txt | grep "gpu_mem" | cut -d "=" -f 2`
	fi

	uname -a

	if [ -e "/etc/issue" ]; then
		cat /etc/issue
	fi

	echo "-----------------------------------------------"
fi

#------------------------------- Download/Update plugins --------------------------------------------

if [ 1 -eq 1 ]; then
	# update this installer
	RESULT=`git pull origin`

	if [ "$RESULT" != "Already up-to-date." ]; then
		echo ""
		echo "    Installer updated. Please re-run build.sh"
		echo ""
		exit
	fi
fi

if [ $M64P_COMPONENTS_FILE -eq 1 ]; then
	for component in ${M64P_COMPONENTS}; do
		plugin=`echo "${component}" | cut -d , -f 1`
		repository=`echo "${component}" | cut -d , -f 2`
		branch=`echo "${component}" | cut -d , -f 3`

		if [ -z "$plugin" ]; then
			continue
		fi

		if [ -z "$repository" ]; then
			repository=$REPO
		fi

		if [ -z "$branch" ]; then
			branch="master"
		fi

		if [ ! -e "${BUILDDIR}/$repository/mupen64plus-${plugin}" ]; then
			echo "************************************ Downloading ${plugin} from ${repository} to ${BUILDDIR}/$repository/mupen64plus-${plugin}"
			git clone https://github.com/${repository}/mupen64plus-${plugin} ${BUILDDIR}/$repository/mupen64plus-${plugin}
		else
			if [ "$DEV" = "0" ]; then
				pushd "${BUILDDIR}/$repository/mupen64plus-$plugin"
				echo "checking $plugin from $repository is up-to-date"
				echo `git pull origin $branch `
				popd
			fi
		fi

		if [ -n "$upstream" ] && [ "$DEV" = "1" ]; then
                       	pushd ${BUILDDIR}/$repository/mupen64plus-$plugin
			if [ `git remote | grep upstream` = "" ]; then
                        	echo "Setting upstream remote on repository"
                        	git remote add upstream https://github.com/$upstream/mupen64plus-$plugin
				popd
			fi
                        git fetch upstream
                   	popd
                fi
	done
fi

#-------------------------------------- set API Directory ----------------------------------------
if [ $M64P_COMPONENTS_FILE -eq 1 ]; then
	for component in ${M64P_COMPONENTS}; do
		plugin=`echo "${component}" | cut -d , -f 1`
		repository=`echo "${component}" | cut -d , -f 2`

		if [ "$plugin" = "core" ]; then
			set APIDIR="../../../../$repository/mupen64plus-core/src/api"
			break
		fi
	done
else
	set APIDIR="../../../../mupen64plus-core/src/api"
fi

#-------------------------------------- Change Branch --------------------------------------------

if [ $M64P_COMPONENTS_FILE -eq 1 ]; then
	for component in ${M64P_COMPONENTS}; do
		plugin=`echo "${component}" | cut -d , -f 1`
		repository=`echo "${component}" | cut -d , -f 2`
		branch=`echo "${component}" | cut -d , -f 3`

		if [ -z "$plugin" ]; then
			continue
		fi

		if [ -z "$branch" ]; then
			branch="master"
		fi

		if [ "$M64P_COMPONENTS_FILE" = "0" ]; then
		repository="."
		fi

		if [ "$DEV" = "0" ]; then
			pushd "${BUILDDIR}/$repository/mupen64plus-${plugin}"
			currentBranch=`git branch | grep [*] | cut -b 3-;`

			if [ ! "$branch" = "$currentBranch" ]; then
				echo "************************************ Changing branch from ${currentBranch} to ${branch} for mupen64plus-${plugin}"
				git checkout $branch
			fi
			popd
		fi
	done
fi
#--------------------------------------- Check free memory --------------------------------------------

RESULT=`free -m -t | grep "Total:" | sed -r 's: +:\t:g' | cut -f 2`

if [ $RESULT -lt $MEM_REQ ]; then
	echo "Not enough memory to build"

	#does /etc/dphys-swapfile specify a value?
	if [ -e "/etc/dphys-swapfile" ]; then
		SWAP_RESULT="grep CONF_SWAPSIZE /etc/dphys-swapfile"
		REQ=`expr $MEM_REQ - $RESULT`

		if [ `echo "$SWAP_RESULT" | cut -c1 ` = "#" ]; then
			echo "Please enable CONF_SWAPSIZE=$REQ in /etc/dphys-swapfile and run 'sudo dphys-swapfile setup; sudo reboot'"
		else
			echo "Please set CONF_SWAPSIZE to >= $REQ in /etc/dphys-swapfile and run 'sudo dphys-swapfile setup; sudo reboot'"
		fi
	fi
	exit
fi

#--------------------------------------- Build plugins --------------------------------------------

for component in ${M64P_COMPONENTS}; do
	plugin=`echo "${component}" | cut -d , -f 1`
	repository=`echo "${component}" | cut -d , -f 2`

	if [ -z "$plugin" ]; then
		continue
	fi

	if [ "${plugin}" = "core" ]; then
		component_type="library"
	elif  [ "${plugin}" = "rom" ]; then
		continue

	elif  [ "${plugin}" = "ui-console" ]; then
		component_type="front-end"
	else
		component_type="plugin"
	fi

	if [ $M64P_COMPONENTS_FILE -eq 0 ]; then
		repository="."
	fi

	echo "************************************ Building ${plugin} ${component_type}"

	#if this is the console then do a clean so that COREDIR will be compiled correctly
	if [ "$CLEAN" = "1" ] || [ "${plugin}" = "ui-console" ]; then
		"$MAKE" -C ${BUILDDIR}/$repository/mupen64plus-${plugin}/projects/unix clean $@
	fi

	# In ricrpi/mupen64plus-core we cannot compile with -03 on pi however some 03 optimizations can be applied i.e. 
	# RPIFLAGS ?= -fgcse-after-reload -finline-functions -fipa-cp-clone -funswitch-loops -fpredictive-commoning -ftree-loop-distribute-patterns -ftree-vectorize
	# These break in versions < 4.7.3 so override RPIFLAGS
	if [ `echo "$GCC 4.7.3" | awk '{print ($1 < $2)}'` -eq 1 ]; then
		"$MAKE" -C ${BUILDDIR}/$repository/mupen64plus-${plugin}/projects/unix all $@ COREDIR=$COREDIR RPIFLAGS=" " SDL_CFLAGS="$SDL_CFLAGS" SDL_LDLIBS="$SDL_LDLIBS"
	else
		"$MAKE" -C ${BUILDDIR}/$repository/mupen64plus-${plugin}/projects/unix all $@ COREDIR=$COREDIR SDL_CFLAGS="$SDL_CFLAGS" SDL_LDLIBS="$SDL_LDLIBS"
	fi

	# dev_build can install into test folder
	if [ "$DEV" = "1" ]; then
		"$MAKE" -C ${BUILDDIR}/$repository/mupen64plus-${plugin}/projects/unix install $@ ${MAKE_INSTALL} DESTDIR="$(pwd)/test/"
	fi
done
