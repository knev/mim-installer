#!/bin/bash

# https://stackoverflow.com/questions/2188199/how-to-use-double-or-single-brackets-parentheses-curly-braces

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
	echo "usage: $0 [-m|--minecraft DIRECTORY] [-d|--directory DIRECTORY] [-u|--upgrade]"
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

INST_VERSION=3

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
	[ "$INST_VERSION" -lt "$NET_INST_VERSION" ] && error_msg "This installer is outdated [v$INST_VERSION]. Please obtain the newer [v$NET_INST_VERSION]."
fi

#--------------------------------------------------------------------------------------------------------------------------------

# https://stackoverflow.com/questions/394230/how-to-detect-the-os-from-a-bash-script
#if [[ "$OSTYPE" == "linux-gnu" ]]; then

#TODO: use /proc/version or g++ --version or uname -v instead to find linux version?
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
MC_DIR="" # Ubuntu: $PATH/.minecraft
UPGRADE=0
SIDE="down"
while [ "$1" != "" ]; do
	case $1 in
		-d | --directory )		shift
								MITM_DIR=$1
								;;
		-m | --minecraft )		shift
								MC_DIR=$1
								;;
		-u | --upgrade )		UPGRADE=1
								;;
		--upstream )			SIDE="up"
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

create_working_directory() 
{
	if [ -d $MITM_DIR/$MCP_DIR/bin/minecraft ]; then
		read -s -n 1 -p "Target directory [$MITM_DIR] exists, overwrite? [N/y] " INPUT || error_exit
		RES=$( tr '[:upper:]' '[:lower:]' <<<"$INPUT" )
		if [[ "$RES" != "y" ]]; then
			echo $'\n'"Abort."
			exit 0
		fi
		echo
	fi
	echo "Setting up working directory: [$MITM_DIR] ..."
	mkdir -p $MITM_DIR || error_msg "failed to make target directory: [$MITM_DIR]"
}

#--------------------------------------------------------------------------------------------------------------------------------

compile_jzmq_lib()
{
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

	rm -rf $JZMQ
}

#--------------------------------------------------------------------------------------------------------------------------------

download_mcp()
{
	echo == Downloading MCP940 for Minecraft v1.12 ==
	[ -d $MCP_DIR ] && { rm -rf $MCP_DIR || error_exit; }
	mkdir -p $MCP_DIR || error_msg "failed to make target directory: [$MCP_DIR]"
	if [ -f mcp940.zip ]; then
		echo "File [mcp940.zip] exists, ... reusing"
	else
	curl -f -o mcp940.zip -L http://www.modcoderpack.com/files/mcp940.zip || error_exit
	fi
	unzip -qo -d $MCP_DIR/. mcp940.zip || error_exit

	rm mcp940.zip
}

#--------------------------------------------------------------------------------------------------------------------------------

upgrade_astyle()
{
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

		rm $ASTYLE

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

		rm $ASTYLE

	else 
		#TODO https://sourceforge.net/projects/astyle/files/astyle/astyle%202.05.1/AStyle_2.05.1_windows.zip/download
		echo Do nothing ...
	fi
}

#--------------------------------------------------------------------------------------------------------------------------------

prep_mcp()
{
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
	WORKING_DIR=()
	# https://unix.stackexchange.com/questions/531944/bash-command-splitting-up-giving-errors
	[ -n "$MC_DIR" ] && { WORKING_DIR=(-w "$MC_DIR"); echo 'Minecraft working directory set to ['$MC_DIR']'; }
	./decompile.sh "${WORKING_DIR[@]}" --norecompile || error_exit 
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
}

#--------------------------------------------------------------------------------------------------------------------------------

download_mim() 
{
	echo "== Downloading Man in the Middle ["$SIDE"stream] component =="
	[ -f ./mitm-$SIDE'stream.jar' ] && { cp ./mitm-$SIDE'stream.jar' ./mitm-$SIDE'stream.jar~' || return 1; }
	curl -f -o ./mitm-$SIDE'stream.jar.tmp' -L $NET_DOWNLOAD/mitm-$SIDE'stream'/mitm-$SIDE'stream.jar' || return 1
	mv ./mitm-$SIDE'stream.jar.tmp' ./mitm-$SIDE'stream.jar' || retun 1
}

#--------------------------------------------------------------------------------------------------------------------------------

generate_run_script() 
{
	echo "== Generating ["$SIDE"stream] run script =="
	[ -f $SIDE'stream.sh' ] && { cp $SIDE'stream.sh' $SIDE'stream.sh~' || return 1; }
	# https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n
	echo '#!/bin/bash'$'\n' > $SIDE'stream.sh'

	#
	# basically don't have to have to escape anything except for single quotes, which aren't escaped inside single quotes
	# https://unix.stackexchange.com/questions/187651/how-to-echo-single-quote-when-using-single-quote-to-wrap-special-characters-in
	# http://tldp.org/LDP/Bash-Beginners-Guide/html/sect_07_01.html
	#

	# [ -f mitm-downstream.jar ] || { echo "File [mitm-downstream.jar] not found. Abort."; exit 1; }
	#
	echo '[ -f mitm-'$SIDE'stream.jar ] || { echo "File [mitm-'$SIDE'stream.jar] not found. Abort."; exit 1; }'$'\n' >> $SIDE'stream.sh'

	# INST_VERSION=`java -classpath mitm-downstream.jar se.mitm.version.Version 2>&1 | grep -m1 MiTM-of-minecraft | sed 's/MiTM-of-minecraft: \(.*\)$/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
	# NET_VERSION=`curl -sfL https://mitm.se/mim-install/mitm-stream/Version.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
	# [ -n "$NET_VERSION" ] && [ "$INST_VERSION" != "$NET_VERSION" ] && { echo "upstream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }
	#
	echo 'INST_VERSION=`java -classpath mitm-'$SIDE'stream.jar se.mitm.version.Version 2>&1 | grep -m1 MiTM-of-minecraft | sed '\''s/MiTM-of-minecraft: \(.*\)$/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
	echo 'NET_VERSION=`curl -sfL '$NET_DOWNLOAD'/mitm-'$SIDE'stream/Version.java | grep -m1 commit | sed '\''s/.*commit=[ ]*\"\([^"]*\)\";/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
	echo '[ -n "$NET_VERSION" ] && [ "$INST_VERSION" != "$NET_VERSION" ] && { echo "'$SIDE'stream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $SIDE'stream.sh'

	# VARIABLES to shorten classpath
	#
	echo 'MiM='`pwd` >> ./$SIDE'stream.sh'
	echo '[ -d $MiM ] || echo "Error: Invalid target directory "$MiM' >> $SIDE'stream.sh'
	echo 'MCP=$MiM/mcp940' >> ./$SIDE'stream.sh'
	echo 'MCPLIBS=$MCP/jars/libraries'$'\n' >> ./$SIDE'stream.sh'

	if [[ $ARCH == macOS ]]; then
		# export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
		# JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^java version \"\(.*\)\".*$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
		# [ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; } 

		#TODO: just use $JAVA_HOME here? instead of reading it again?
		echo 'export JAVA_HOME=`/usr/libexec/java_home -v 1.8`' >> $SIDE'stream.sh' 
		echo 'JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed '\''s/^java version \"\(.*\)\".*$/\1/'\'' | sed '\''s/\([0-9].[0-9]\).*/\1/'\''`' >> $SIDE'stream.sh'
		echo '[ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $SIDE'stream.sh' 

	elif [[ $ARCH == "Linux" ]]; then
		echo 'export JAVA_HOME="'$JAVA_HOME'"' >> $SIDE'stream.sh' 
		echo '[ -n "JAVA_HOME" ] && export PATH=$JAVA_HOME/bin:$PATH' >> $SIDE'stream.sh'
		echo 'JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed '\''s/^java version \"\(.*\)\".*$/\1/'\'' | sed '\''s/\([0-9].[0-9]\).*/\1/'\''`' >> $SIDE'stream.sh'
		echo '[ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $SIDE'stream.sh' 

	fi

	echo -n 'java -Xms1G -Xmx1G' '-Djava.library.path="'\$MiM'/libs"' '-classpath "'`find mcp940/jars/libraries -type f -name "*.jar" -print0 | sed 's/mcp940\/jars\/libraries/$MCPLIBS/g' | tr '\000' ':'`'$MCP/bin/minecraft:$MCP/jars:$MiM/mitm-'$SIDE'stream.jar" ' >> ./$SIDE'stream.sh'
	if [[ $SIDE = "down" ]]; then
		echo 'se.mitm.server.DedicatedServerProxy' >> ./$SIDE'stream.sh'
	else
		echo 'se.mitm.client.MinecraftClientProxy' >> ./$SIDE'stream.sh'
	fi

	chmod +x ./$SIDE'stream.sh'

	echo 'echo "java -classpath mitm-'$SIDE'stream.jar" >> ./'$SIDE'stream.sh'
}

#--------------------------------------------------------------------------------------------------------------------------------

upgrade()
{
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
				download_mim || { echo "FAIL!"; continue; }
				echo $SIDE"stream: "`java -classpath mitm-$SIDE'stream.jar' se.mitm.version.Version`
				generate_run_script
			else
				INST_VERSION=`java -classpath mitm-$SIDE'stream.jar' se.mitm.version.Version | sed 's/MiTM-of-minecraft: \(.*\)$/\1/'`
				echo $SIDE"stream: ["$INST_VERSION"]; Up to date!"
			fi
		fi
	done

	exit 0;
}

#--------------------------------------------------------------------------------------------------------------------------------

REQ=java; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
REQ=javac; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
#REQ=jar; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"

if [[ $ARCH == macOS ]]; then
	# https://stackoverflow.com/questions/21964709/how-to-set-or-change-the-default-java-jdk-version-on-os-x
	export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
	JAVA_HOME_ERROR='JAVA_HOME is determined by "/usr/libexec/java_home"'
elif [[ $ARCH == "Linux" ]]; then
	# https://stackoverflow.com/questions/41059994/default-java-java-home-vs-sudo-update-alternatives-config-java
	# https://unix.stackexchange.com/questions/212139/how-to-switch-java-environment-for-specific-process
	[ -n "JAVA_HOME" ] && export PATH=$JAVA_HOME/bin:$PATH
	JAVA_HOME_ERROR='JAVA_HOME should point to the JDK root e.g., export JAVA_HOME="/usr/lib/jvm/jdk-8"'
else
	error_msg "Unknown Java JDK support for architecture: [$UNAME]"
fi

echo 'JAVA_HOME='$JAVA_HOME'; '`java -version 2>&1 | head -n 1`
JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^java version \"\(.*\)\".*$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
[ "$JAVA_VERSION" == "1.8" ] || { echo $JAVA_HOME_ERROR; error_msg "This install script requires Java JDK version 1.8"; }

REQ=g++; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=git; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=automake; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=make; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=pkg-config
REQ=autoconf
REQ=curl; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=unzip; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"

REQ=libtool # (a mac version is preinstalled)
if [[ $ARCH == macOS ]]; then
	which glibtool > /dev/null || error_msg "This install script requires [libtool] to be installed"
fi

#TODO host:/usr/local/opt/zmq$ [ -f include/zmq.h ] || echo "NO"
if [[ $ARCH = "macOS" ]]; then
	REQ=zmq # ./configure will fail if not installed
elif [[ $ARCH = "Linux" ]]; then
	REQ=libzmq3-dev # ./configure will fail if not installed
fi

#--------------------------------------------------------------------------------------------------------------------------------

if [[ $UPGRADE == 1 ]]; then
	upgrade || error_exit
fi

create_working_directory || error_exit
cd $MITM_DIR/ || error_exit

compile_jzmq_lib || error_exit
download_mcp || error_exit
upgrade_astyle || error_exit
prep_mcp || error_exit
download_mim || error_exit 
generate_run_script || error_exit

cd ..

#--------------------------------------------------------------------------------------------------------------------------------

echo "SUCCESS!"; exit 0
