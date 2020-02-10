#!/bin/bash

# One of two philosophies:
# 1) install each section; once it is done, don't repeat it.
# 2) install each section, but clobber existing files to ensure a clean install.
# Going with option 2.

#--------------------------------------------------------------------------------------------------------------------------------

pause() {
	read -n 1 -p "Press [KEY] to continue ..."
	echo
}

usage() {
	echo "usage: $0 [-d|--directory directory] [-u|--upgrade]"
}

error_msg() {
	echo $0": $1" 1>&2
	echo "FAIL!"
	exit 1
}
error_exit() {
	echo "FAIL!"
	exit 1
}

#--------------------------------------------------------------------------------------------------------------------------------

INST_VERSION=1

NET_INST_URL=https://raw.githubusercontent.com/knev/mim-installer/master/install.sh
NET_INST_VERSION=`curl -sfL --url $NET_INST_URL | grep -m1 INST_VERSION | sed 's/INST_VERSION=\([0-9]*\)/\1/'  `
NET_DOWNLOAD=https://mitm.se/mim-install # curl has -L switch, so should be ok to leave off the www

if [ "$NET_INST_VERSION" == "" ]; then
	echo "Unable to check for installer updates, currently [v$INST_VERSION]"
	read -s -n 1 -p "Please check manually for a newer version, continue? [N/y] " INPUT || error_exit
	RES=$( tr '[:upper:]' '[:lower:]' <<<"$INPUT" )
	if [[ "$RES" != "y" ]]; then
		echo
		echo "Abort."
		exit 0
	fi
	echo
else
	[ "$INST_VERSION" == "$NET_INST_VERSION" ] || error_msg "This installer is outdated [v$INST_VERSION]. Please obtain the newer [v$NET_INST_VERSION]."
fi

#--------------------------------------------------------------------------------------------------------------------------------

# https://stackoverflow.com/questions/394230/how-to-detect-the-os-from-a-bash-script
#if [[ "$OSTYPE" == "linux-gnu" ]]; then

# https://en.wikipedia.org/wiki/Uname
#
UNAME="$(uname -s)"
case "${UNAME}" in
	Linux*)		ARCH=Linux;;
	Darwin*)	ARCH=macOS;;
#	CYGWIN*)	ARCH=Cygwin;;
#	MINGW*)		ARCH=MinGw;;
#	*)			ARCH="UNKNOWN:${unameOut}"
	*)			error_msg "unsupported architecture: [$UNAME]"
esac

# http://linuxcommand.org/lc3_wss0120.php
#
MITM_DIR=MiM
MCP_DIR=mcp940
UPGRADE=0
SIDE="down"
while [ "$1" != "" ]; do
	case $1 in
		-d | --directory )		shift
								MITM_DIR=$1
								;;
		-u | --upgrade)			UPGRADE=1
								;;
		--upstream)				SIDE="up"
								;;
		-h | --help )			usage
								exit 0
								;;
		* )						usage
								exit 1
	esac
	shift
done

#--------------------------------------------------------------------------------------------------------------------------------
# Upgrade?

REQ=java; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
REQ=javac; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
REQ=jar; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"

#TODO which (other) java versions are supported?

JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^java version \"\(.*\)\"$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
[ "$JAVA_VERSION" == "1.8" ] || error_msg "only Java JDK version 1.8 is currently supported"

if [[ $UPGRADE == 1 ]]; then
	[ -d $MITM_DIR/$MCP_DIR/bin/minecraft ] || error_msg "Target directory [$MITM_DIR] not found"
	cd $MITM_DIR/ || error_exit


	for SIDE in "down" "up"
	do
		if [ -f ./mitm-$SIDE'stream.jar' ]; then
			INST_VERSION=`java -classpath mitm-$SIDE'stream.jar' se.mitm.version.Version | sed 's/MiTM-of-minecraft: \(.*\)$/\1/'`
			#INST_MAJOR=`echo $INST_VERSION | sed 's/^v\([0-9]*\).*$/\1/'`
			#INST_MINOR=`echo $INST_VERSION | sed 's/^v[0-9]*\.\([0-9]*\)-.*$/\1/'`

			NET_VERSION=`curl -sfL $NET_DOWNLOAD/mitm-$SIDE'stream'/Version.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/'`
			#NET_MAJOR=`echo $NET_VERSION | sed 's/^v\([0-9]*\).*$/\1/'`
			#NET_MINOR=`echo $NET_VERSION | sed 's/^v[0-9]*\.\([0-9]*\)-.*$/\1/'`

			#echo $INST_VERSION - $NET_VERSION - $INST_MAJOR $INST_MINOR - $NET_MAJOR $NET_MINOR
			#if [ "$INST_MAJOR" -lt "$NET_MAJOR" ]; then
			if [ "$INST_VERSION" != "$NET_VERSION" ]; then
				echo "== Downloading Man in the Middle ["$SIDE"stream] component =="
				curl -f -o ./mitm-$SIDE'stream.jar.tmp' -L $NET_DOWNLOAD/mitm-$SIDE'stream'/mitm-$SIDE'stream.jar' || continue
				rm ./mitm-$SIDE'stream.jar' || continue
				mv ./mitm-$SIDE'stream.jar.tmp' ./mitm-$SIDE'stream.jar' || continue
				echo $SIDE"stream: "`java -classpath mitm-$SIDE'stream.jar' se.mitm.version.Version`
			else
				INST_VERSION=`java -classpath mitm-$SIDE'stream.jar' se.mitm.version.Version | sed 's/MiTM-of-minecraft: \(.*\)$/\1/'`
				echo $SIDE"stream: ["$INST_VERSION"]; Up to date!"
			fi
		fi
	done

	exit 0;
fi

#--------------------------------------------------------------------------------------------------------------------------------
# $MITM_DIR, pre-req

if [ -d $MITM_DIR/$MCP_DIR/bin/minecraft ]; then
	read -s -n 1 -p "Target directory [$MITM_DIR] exists, overwrite? [N/y] " INPUT || error_exit
	RES=$( tr '[:upper:]' '[:lower:]' <<<"$INPUT" )
	if [[ "$RES" != "y" ]]; then
		echo $'\n'"Abort."
		exit 0
	fi
fi
echo $'\n'"Setting up working directory: [$MITM_DIR] ..."
mkdir -p $MITM_DIR || error_msg "failed to make target directory: [$MITM_DIR]"
cd $MITM_DIR/ || error_exit

REQ=git; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=automake; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=g++; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=make; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"

REQ=libtool # (a mac version is preinstalled)
if [[ $ARCH == macOS ]]; then
which glibtool > /dev/null || error_msg "This install script requires [libtool] to be installed"
fi

REQ=pkg-config
REQ=autoconf

#--------------------------------------------------------------------------------------------------------------------------------
# jzmq

#TODO host:/usr/local/opt/zmq$ [ -f include/zmq.h ] || echo "NO"

if [[ $ARCH = "macOS" ]]; then
REQ=zmq # ./configure will fail if not installed
elif [[ $ARCH = "Linux" ]]; then
REQ=libzmq3-dev # ./configure will fail if not installed
fi

echo == Compiling Java binding for zmq ==
JZMQ=jzmq.git
# https://linuxize.com/post/bash-check-if-file-exists/
if [ -d $JZMQ ]; then
	echo "Clean existing [$JZMQ] directory"
	pushd $JZMQ > /dev/null || error_exit
	git clean -fdxq || error_exit
	git checkout . || error_exit
	popd > /dev/null
else
	git clone https://github.com/zeromq/jzmq.git $JZMQ || error_exit
fi
pushd $JZMQ/jzmq-jni/ > /dev/null || error_exit
mv configure.in configure.ac || error_exit
./autogen.sh || error_exit
./configure || error_exit
make || error_exit
cp -r src/main/c++/.libs ../../libs || error_exit
popd > /dev/null
#cleanup rm -rf $JZMQ

#--------------------------------------------------------------------------------------------------------------------------------
# $MCP_DIR

REQ=curl; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=unzip; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"

echo == Downloading MCP940 for Minecraft v1.12 ==
[ -d $MCP_DIR ] && (rm -rf $MCP_DIR || error_exit)
mkdir -p $MCP_DIR || error_msg "failed to make target directory: [$MCP_DIR]"
if [ -f mcp940.zip ]; then
	echo "File [mcp940.zip] exists, ... reusing"
else
	curl -f -o mcp940.zip -L http://www.modcoderpack.com/files/mcp940.zip || error_exit
fi
unzip -qo -d $MCP_DIR/. mcp940.zip || error_exit
#cleanup rm mcp940.zip

#--------------------------------------------------------------------------------------------------------------------------------
# upgrade astyle

echo == Upgrading astyle to version 2.05.1 ==
ASTYLE=astyle_2.05.1_XXX.tar.gz
if [[ $ARCH == "Linux" ]]; then
	ASTYLE=astyle_2.05.1_linux.tar.gz
	[ -f $ASTYLE ] || curl -f -o $ASTYLE -L https://sourceforge.net/projects/astyle/files/astyle/astyle%202.05.1/$ASTYLE/download || error_exit
	tar -xzf $ASTYLE || error_exit
	pushd astyle/build/gcc > /dev/null || error_exit
	make || error_exit
	cp bin/astyle ../../../mcp940/runtime/bin/. || error_exit
	popd > /dev/null
	sed -i 's/^AStyle_linux  = astyle/AStyle_linux	= \%\(DirRuntime\)s\/bin\/astyle/g' mcp940/conf/mcp.cfg
	rm -rf astyle
	#cleanup rm $ASTYLE
elif [[ $ARCH == "macOS" ]]; then
	mv mcp940/runtime/bin/astyle-osx mcp940/runtime/bin/astyle-osx-2.02 || error_exit
	ASTYLE=astyle_2.05.1_macosx.tar.gz
	[ -f $ASTYLE ] || curl -f -o $ASTYLE -L https://sourceforge.net/projects/astyle/files/astyle/astyle%202.05.1/$ASTYLE/download || error_exit
	tar -xzf $ASTYLE || error_exit
	pushd astyle/build/mac > /dev/null || error_exit
	make || error_exit
	cp bin/astyle ../../../mcp940/runtime/bin/astyle-osx || error_exit
	popd > /dev/null
	rm -rf astyle
	#cleanup rm $STYLE
else 
	#TODO https://sourceforge.net/projects/astyle/files/astyle/astyle%202.05.1/AStyle_2.05.1_windows.zip/download
	echo Do nothing ...
fi

#--------------------------------------------------------------------------------------------------------------------------------
# prep MCP src

cd mcp940 || error_exit

echo == Downloading Minecraft Server v1.12 == # https://mcversions.net/
curl -f -o jars/minecraft_server.1.12.jar -L https://launcher.mojang.com/v1/objects/8494e844e911ea0d63878f64da9dcc21f53a3463/server.jar || error_exit

echo == Downloading MinecraftDiscovery.py.patch ==
curl -f -o MinecraftDiscovery.py.patch -L https://gist.githubusercontent.com/PLG/6196bc01810c2ade88f0843253b56097/raw/1bd38308838f793a484722aa46eae503328bb50f/MinecraftDiscovery.py.patch || error_exit
git status > /dev/null 2>&1 && error_msg "Target directory can not be part of a git repo; patching will fail" # reported to git community
echo Patching ...
git apply --stat --apply --reject MinecraftDiscovery.py.patch || error_exit

REQ=python2; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"

#REQ assets/minecraft should exist, it could be hiding in the <version>.jar file; Linux?

# echo Decompiling Minecraft ...
./decompile.sh --norecompile || error_exit 
# decompile.sh doesn't return an error code when 1.12.jar not found e.g., "Please run launcher & Minecraft at least once"
[ ! -d src/minecraft ] && error_exit
[ ! -d src/minecraft_server ] && error_exit

echo == Copying Minecraft assets ==
cp -r temp/src/minecraft/assets/minecraft jars/assets/. || error_exit
touch jars/assets/.mcassetsroot

# echo Duplicating Minecraft ...
cp src/minecraft_server/net/minecraft/network/rcon/IServer.java src/minecraft/net/minecraft/network/rcon/. || error_exit
cp src/minecraft_server/net/minecraft/network/rcon/RConOutputStream.java src/minecraft/net/minecraft/network/rcon/. || error_exit
cp src/minecraft_server/net/minecraft/network/rcon/RConThreadBase.java src/minecraft/net/minecraft/network/rcon/. || error_exit
cp src/minecraft_server/net/minecraft/network/rcon/RConThreadClient.java src/minecraft/net/minecraft/network/rcon/. || error_exit
cp src/minecraft_server/net/minecraft/network/rcon/RConThreadMain.java src/minecraft/net/minecraft/network/rcon/. || error_exit
cp src/minecraft_server/net/minecraft/network/rcon/RConThreadQuery.java src/minecraft/net/minecraft/network/rcon/. || error_exit
cp src/minecraft_server/net/minecraft/network/rcon/RConUtils.java src/minecraft/net/minecraft/network/rcon/. || error_exit
cp src/minecraft_server/net/minecraft/server/ServerEula.java src/minecraft/net/minecraft/server/. || error_exit
cp -r src/minecraft_server/net/minecraft/server/dedicated src/minecraft/net/minecraft/server/. || error_exit
cp -r src/minecraft_server/net/minecraft/server/gui src/minecraft/net/minecraft/server/. || error_exit

echo == Downloading merge-client-server.patch ==
curl -f -o ./merge-client-server-astyle.patch -L $NET_DOWNLOAD/merge-client-server-astyle.patch || error_exit
echo Patching ...
git apply --stat --ignore-space-change -p2 --apply --reject merge-client-server-astyle.patch || error_exit

echo == Downloading /broken-packets-no-lwjgl.patch ==
curl -f -o ./broken-packets-no-lwjgl.patch -L $NET_DOWNLOAD/broken-packets-no-lwjgl.patch || error_exit
echo Patching ...
git apply --stat --ignore-space-change -p2 --apply --reject ./broken-packets-no-lwjgl.patch || error_exit

# echo Recompiling Minecraft ...
./recompile.sh || error_exit
[ ! -d bin/minecraft ] && error_exit
[ ! -d bin/minecraft_server ] && error_exit

cd ..

#--------------------------------------------------------------------------------------------------------------------------------
# MITM components

echo == Downloading Man in the Middle component ==
curl -f -o ./mitm-$SIDE'stream.jar' -L $NET_DOWNLOAD/mitm-$SIDE'stream'/mitm-$SIDE'stream.jar' || error_exit

echo == Generating classpath \& run script ==
# https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n
echo '#!/bin/bash'$'\n' > $SIDE'stream.sh'

# basically don't have to have to escape anything except for single quotes, which aren't escaped inside single quotes
# https://unix.stackexchange.com/questions/187651/how-to-echo-single-quote-when-using-single-quote-to-wrap-special-characters-in
#
# INST_VERSION=`java -classpath mitm-$SIDE'stream.jar' se.mitm.version.Version | sed 's/MiTM-of-minecraft: \(.*\)$/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
# NET_VERSION=`curl -sfL $NET_DOWNLOAD/mitm-$SIDE'stream'/Version.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
# [ "$INST_VERSION" == "$NET_VERSION" ] || ( echo "upstream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..." && read -s -n 1 -p "Press [KEY] to continue ..." && echo )
#
echo 'INST_VERSION=`java -classpath mitm-'$SIDE'stream.jar se.mitm.version.Version | sed '\''s/MiTM-of-minecraft: \(.*\)$/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
echo 'NET_VERSION=`curl -sfL '$NET_DOWNLOAD'/mitm-'$SIDE'stream/Version.java | grep -m1 commit | sed '\''s/.*commit=[ ]*\"\([^"]*\)\";/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
echo '[ "$INST_VERSION" == "$NET_VERSION" ] || ( echo "upstream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..." && read -s -n 1 -p "Press [KEY] to continue ..." && echo )'$'\n' >> $SIDE'stream.sh'

# #VARIABLES to shorten classpath
#
echo 'MiTM='`pwd` >> ./$SIDE'stream.sh'
echo '[ -d $MiTM ] || echo "Error: Invalid target directory "$MiTM' >> $SIDE'stream.sh'
echo 'MCP=$MiTM/mcp940' >> ./$SIDE'stream.sh'
echo 'MCPLIBS=$MCP/jars/libraries'$'\n' >> ./$SIDE'stream.sh'

echo -n 'java -Xms1G -Xmx1G' '-Djava.library.path="'\$MiTM'/libs"' '-classpath "'`find mcp940/jars/libraries -type f -name "*.jar" -print0 | sed 's/mcp940\/jars\/libraries/$MCPLIBS/g' | tr '\000' ':'`'$MCP/bin/minecraft:$MCP/jars:$MiTM/mitm-'$SIDE'stream.jar" ' >> ./$SIDE'stream.sh'
if [[ $SIDE = "down" ]]; then
	echo 'se.mitm.server.DedicatedServerProxy' >> ./$SIDE'stream.sh'
else
	echo 'se.mitm.client.MinecraftClientProxy' >> ./$SIDE'stream.sh'
fi

chmod +x ./$SIDE'stream.sh'

#--------------------------------------------------------------------------------------------------------------------------------

rm $ASTYLE
rm -rf $JZMQ
rm mcp940.zip

cd ..

echo "SUCCESS!"; exit 0
