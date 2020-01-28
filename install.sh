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
	#echo "usage: $0 [[[-d directory ] [-i]] | [-h]]"
	echo "usage: $0 [-d|--directory directory ] [-u|--upgrade]"
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
MITM_DIR=MiTM-of-minecraft
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
# $MITM_DIR, pre-req

REQ=java; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
REQ=javac; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
REQ=jar; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"

#TODO which java versions are supported?

if [[ $UPGRADE == 1 ]]; then
	echo "UPGRADE"

	exit 0;
fi
	
if [ -d $MITM_DIR/$MCP_DIR/bin/minecraft ]; then
	read -n 1 -p "Target directory [$MITM_DIR] exists, overwrite? [N/y] " INPUT || error_exit
	RES=$( tr '[:upper:]' '[:lower:]' <<<"$INPUT" )
	if [[ "$RES" != "y" ]]; then
		echo
		echo "Abort."
		exit 0
	fi
fi
echo Setting up working directory: [$MITM_DIR] ...
mkdir -p $MITM_DIR || error_msg "failed to make target directory: [$MITM_DIR]"
cd $MITM_DIR/ || error_exit

REQ=git; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=automake; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=g++; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=make; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"

REQ=libtool # (a mac version is preinstalled)
if [[ $ARCH == macOS ]]; then
which glibtool || error_msg "This install script requires [libtool] to be installed"
fi

REQ=pkg-config
REQ=autoconf

#--------------------------------------------------------------------------------------------------------------------------------
# jzmq

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
make
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
	curl -f -o mcp940.zip http://www.modcoderpack.com/files/mcp940.zip || error_exit
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
	make
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
	make
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
curl -f -o jars/minecraft_server.1.12.jar https://launcher.mojang.com/v1/objects/8494e844e911ea0d63878f64da9dcc21f53a3463/server.jar || error_exit

echo == Downloading MinecraftDiscovery.py.patch ==
curl -f -o MinecraftDiscovery.py.patch https://gist.githubusercontent.com/PLG/6196bc01810c2ade88f0843253b56097/raw/1bd38308838f793a484722aa46eae503328bb50f/MinecraftDiscovery.py.patch || error_exit
# this will fail, if it is run in a directory that is already part of a git repo; reported to git community
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
curl -f -o ./merge-client-server-astyle.patch https://www.mitm.se/minecraft/merge-client-server-astyle.patch || error_exit
echo Patching ...
git apply --stat --ignore-space-change -p2 --apply --reject merge-client-server-astyle.patch || error_exit

echo == Downloading /broken-packets-no-lwjgl.patch ==
curl -f -o ./broken-packets-no-lwjgl.patch https://www.mitm.se/minecraft/broken-packets-no-lwjgl.patch || error_exit
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
curl -f -o ./mitm-$SIDE'stream.jar' https://www.mitm.se/minecraft/mitm-$SIDE'stream.jar' || error_exit

echo == Generating classpath \& run script ==
# https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n
echo '#!/bin/bash' > $SIDE'stream.sh'
echo 'MiTM='`pwd` >> ./$SIDE'stream.sh'
echo '[ -d $MiTM ] || echo "Error: Invalid target directory "$MiTM' >> $SIDE'stream.sh'
echo 'MCP=$MiTM/mcp940' >> ./$SIDE'stream.sh'
echo 'MCPLIBS=$MCP/jars/libraries'$'\n' >> ./$SIDE'stream.sh'

echo -n 'java -Xms1G -Xmx1G' '-Djava.library.path="'\$MiTM'/libs"' '-classpath "'`find mcp940/jars/libraries -type f -name "*.jar" -print0 | sed 's/mcp940\/jars\/libraries/$MCPLIBS/g' | tr '\000' ':'`'$MCP/bin/minecraft:$MCP/jars:$MiTM/mitm-'$SIDE'stream.jar" ' >> ./$SIDE'stream.sh'
if [[ $SIDE = "down" ]]; then
	#curl -f -o ./mitm-downstream.jar https://www.mitm.se/minecraft/mitm-downstream.jar || error_exit
	echo 'se.mitm.server.DedicatedServerProxy' >> ./$SIDE'stream.sh'
else
	#curl -f -o ./mitm-upstream.jar https://www.mitm.se/minecraft/mitm-upstream.jar || error_exit
	echo 'se.mitm.client.MinecraftClientProxy' >> ./$SIDE'stream.sh'
fi

chmod +x ./$SIDE'stream.sh'

#--------------------------------------------------------------------------------------------------------------------------------

rm $ASTYLE
rm -rf $JZMQ
rm mcp940.zip

cd ..

echo "SUCCESS!"; exit 0
