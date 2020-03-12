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
MIM_DIR=MiM
FORGE_VERSION=1.12-14.21.1.2387
FORGE_SNAPSHOT=gradle.cache/caches/minecraft/net/minecraftforge/forge/$FORGE_VERSION/snapshot/20170624
MC_DIR="" # Ubuntu: $PATH/.minecraft
UPGRADE=0
SIDE="down"
while [ "$1" != "" ]; do
	case $1 in
		-d | --directory )		shift
								MIM_DIR=$1
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

INST_VERSION=6

# (23) Failed writing body: 
# https://stackoverflow.com/questions/16703647/why-does-curl-return-error-23-failed-writing-body
# This happens when a piped program (e.g. grep) closes the read pipe before the previous program is finished writing the whole page.
# ... as soon as grep has what it wants it will close the read stream from curl.
# 
NET_INST_URL=https://raw.githubusercontent.com/knev/mim-installer/master/install.sh
NET_INST_VERSION=`curl -sfL --url $NET_INST_URL 2>/dev/null | sed -nE '/INST_VERSION=[0-9]+/p' | sed 's/^INST_VERSION=\(.*\)$/\1/'  `
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

create_working_directory() 
{
	if [ -f "$MIM_DIR"/forge-$FORGE_VERSION-mdk/$FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION.jar ]; then
		read -s -n 1 -p 'Target directory ['$MIM_DIR'] exists, overwrite? [N/y] ' INPUT || error_exit
		RES=$( tr '[:upper:]' '[:lower:]' <<<"$INPUT" )
		if [[ "$RES" != "y" ]]; then
			echo $'\n'"Abort."
			exit 0
		fi
		echo
	fi
	echo 'Setting up working directory: ['$MIM_DIR'] ...'
	mkdir -p "$MIM_DIR" || error_msg 'failed to make target directory: ['$MIM_DIR']'
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
	[ -d mcp940 ] && { rm -rf mcp940 || error_exit; }
	return 0;
}

download_forge()
{
	echo == Downloading Forge for Minecraft v1.12 ==
	[ -d forge-$FORGE_VERSION-mdk ] && { rm -rf forge-$FORGE_VERSION-mdk || error_exit; }
	mkdir -p forge-$FORGE_VERSION-mdk || error_msg "failed to make target directory: [forge-$FORGE_VERSION-mdk]"
	curl -f -o forge-$FORGE_VERSION-mdk.zip -L https://files.minecraftforge.net/maven/net/minecraftforge/forge/$FORGE_VERSION/forge-$FORGE_VERSION-mdk.zip || error_exit
	unzip -qo -d forge-$FORGE_VERSION-mdk/. forge-$FORGE_VERSION-mdk.zip || error_exit

	rm forge-$FORGE_VERSION-mdk.zip
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

	echo == Downloading broken-packets-no-lwjgl.patch ==
	curl -f -o ./broken-packets-no-lwjgl.patch -L $NET_DOWNLOAD/broken-packets-no-lwjgl.patch || error_exit
	echo Patching ...
	git apply --stat --ignore-space-change -p2 --apply --reject ./broken-packets-no-lwjgl.patch || error_exit

	# echo Recompiling Minecraft ...
	./recompile.sh || error_exit
	[ ! -d bin/minecraft ] && error_exit
	[ ! -d bin/minecraft_server ] && error_exit

	cd ..
}

prep_forge()
{
	cd forge-$FORGE_VERSION-mdk || error_exit

	./gradlew -g gradle.cache :fixMcSources
	
	# Skip :applySourcePatches
	#
	cp $FORGE_SNAPSHOT/forge-$FORGE_VERSION-decompFixed.jar $FORGE_SNAPSHOT/forge-$FORGE_VERSION-patched.jar || error_exit

	./gradlew -g gradle.cache :remapMcSources -x :deobfCompileDummyTask -x :deobfProvidedDummyTask -x :extractDependencyATs -x :extractMcpData -x :extractMcpMappings -x :getVersionJson -x :extractUserdev -x :genSrgs -x :downloadClient -x :downloadServer -x :splitServerJar -x :mergeJars -x :deobfMcSRG -x :decompileMc -x :fixMcSources -x :applySourcePatches # -x :remapMcSources -x :recompileMc

	# patch source
	#
	[ -d $FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION-sources ] && { rm -rf $FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION-sources || error_exit; }
	mkdir $FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION-sources || error_exit
	pushd $FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION-sources || error_exit
	jar xf ../forgeSrc-$FORGE_VERSION-sources.jar

	# here we don't want to apply any patches to the code that will break the :recompileMc task

	# https://stackoverflow.com/questions/24821431/git-apply-patch-fails-silently-no-errors-but-nothing-happens
	# Use: patch -p1 < path/file.patch

	BROKEN_PACKETS_NO_LWJGL=forge-broken-packets-no-lwjgl.patch
	echo == Downloading $BROKEN_PACKETS_NO_LWJGL ==
	curl -f -o ./$BROKEN_PACKETS_NO_LWJGL -L $NET_DOWNLOAD/$BROKEN_PACKETS_NO_LWJGL || error_exit
	echo Patching ...
	git apply --stat --ignore-space-change -p1 --apply --reject ./$BROKEN_PACKETS_NO_LWJGL || error_exit

	rm ../forgeSrc-$FORGE_VERSION-sources.jar
	jar cf ../forgeSrc-$FORGE_VERSION-sources.jar *
	popd

	# :applySourcePatches is the task we definitely want to skip!
	./gradlew -g gradle.cache :recompileMc -x :deobfCompileDummyTask -x :deobfProvidedDummyTask -x :extractDependencyATs -x :extractMcpData -x :extractMcpMappings -x :getVersionJson -x :extractUserdev -x :genSrgs -x :downloadClient -x :downloadServer -x :splitServerJar -x :mergeJars -x :deobfMcSRG -x :decompileMc -x :fixMcSources -x :applySourcePatches -x :remapMcSources # -x :recompileMc

	[ ! -f $FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION.jar ] && error_exit

	cd ..
}

#--------------------------------------------------------------------------------------------------------------------------------

download_mim() 
{
	echo "== Downloading MiM ["$SIDE"stream] component =="
	[ -f ./mim-$SIDE'stream.jar' ] && { cp ./mim-$SIDE'stream.jar' ./mim-$SIDE'stream.jar~' || return 1; }
	curl -f -o ./mim-$SIDE'stream.jar.tmp' -L $NET_DOWNLOAD/mim-$SIDE'stream'/mim-$SIDE'stream.jar' || return 1
	mv ./mim-$SIDE'stream.jar.tmp' ./mim-$SIDE'stream.jar' || retun 1
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

	# [ -f mim-downstream.jar ] || { echo "File [mim-downstream.jar] not found. Abort."; exit 1; }
	#
	echo '[ -f mim-'$SIDE'stream.jar ] || { echo "File [mim-'$SIDE'stream.jar] not found. Abort."; exit 1; }'$'\n' >> $SIDE'stream.sh'

	# while [ "$1" != "" ]; do [ "$1" == "--version" ] && { echo `java -classpath mim-upstream.jar se.mitm.version.Version`; exit 0; }; shift; done
	#
	echo 'while [ "$1" != "" ]; do [ "$1" == "--version" ] && { echo `java -classpath mim-'$SIDE'stream.jar se.mitm.version.Version`; exit 0; }; shift; done'$'\n' >> $SIDE'stream.sh' 
	
	# INST_VERSION=`java -classpath mim-downstream.jar se.mitm.version.Version 2>&1 | grep -m1 "Man in the Middle of Minecraft (MiM)" | sed 's/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
	# NET_VERSION=`curl -sfL https://mitm.se/mim-install/mim-stream/Version.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
	# [ -n "$NET_VERSION" ] && [ "$INST_VERSION" != "$NET_VERSION" ] && { echo "upstream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }
	#
	echo 'INST_VERSION=`java -classpath mim-'$SIDE'stream.jar se.mitm.version.Version 2>&1 | grep -m1 "Man in the Middle of Minecraft (MiM)" | sed '\''s/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
	echo 'NET_VERSION=`curl -sfL '$NET_DOWNLOAD'/mim-'$SIDE'stream/Version.java | grep -m1 commit | sed '\''s/.*commit=[ ]*\"\([^"]*\)\";/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
	echo '[ -n "$NET_VERSION" ] && [ "$INST_VERSION" != "$NET_VERSION" ] && { echo "'$SIDE'stream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $SIDE'stream.sh'

	# VARIABLES to shorten classpath
	#
	echo 'MiM="'`pwd`'"' >> ./$SIDE'stream.sh'
	echo '[ -d "$MiM" ] || echo "Error: Invalid target directory "$MiM' >> $SIDE'stream.sh'
	echo 'LIB=$MiM/forge-'$FORGE_VERSION'-mdk/gradle.cache/caches/modules-2/files-2.1'$'\n' >> ./$SIDE'stream.sh'

	if [[ $ARCH == macOS ]]; then
		# export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
		# JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^java version \"\(.*\)\".*$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
		# [ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; } 

		#TODO: just use $JAVA_HOME here? instead of reading it again?
		echo 'export JAVA_HOME=`/usr/libexec/java_home -v 1.8`' >> $SIDE'stream.sh' 
		echo 'JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed '\''s/^.*version \"\(.*\)\".*$/\1/'\'' | sed '\''s/\([0-9].[0-9]\).*/\1/'\''`' >> $SIDE'stream.sh'
		echo '[ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $SIDE'stream.sh' 

	elif [[ $ARCH == "Linux" ]]; then
		echo 'export JAVA_HOME="'$JAVA_HOME'"' >> $SIDE'stream.sh' 
		echo '[ -n "JAVA_HOME" ] && export PATH=$JAVA_HOME/bin:$PATH' >> $SIDE'stream.sh'
		echo 'JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed '\''s/^.*version \"\(.*\)\".*$/\1/'\'' | sed '\''s/\([0-9].[0-9]\).*/\1/'\''`' >> $SIDE'stream.sh'
		echo '[ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $SIDE'stream.sh' 

	fi

	#FOUND_LIBS=(`find forge-$FORGE_VERSION-mdk/gradle.cache/caches/modules-2/files-2.1 -type f -name "*.jar" `)
	FOUND_LIBS=(
		#forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/minecraft/net/minecraftforge/forge/1.12-14.21.1.2387/snapshot/20170624/forgeSrc-1.12-14.21.1.2387.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.paulscode/soundsystem/20120107/419c05fe9be71f792b2d76cfc9b67f1ed0fec7f6/soundsystem-20120107.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.paulscode/codecjorbis/20101023/c73b5636faf089d9f00e8732a829577de25237ee/codecjorbis-20101023.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.paulscode/codecwav/20101023/12f031cfe88fef5c1dd36c563c0a3a69bd7261da/codecwav-20101023.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.paulscode/libraryjavasound/20101123/5c5e304366f75f9eaa2e8cca546a1fb6109348b3/libraryjavasound-20101123.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.paulscode/librarylwjglopenal/20100824/73e80d0794c39665aec3f62eee88ca91676674ef/librarylwjglopenal-20100824.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/ca.weblite/java-objc-bridge/1.0.0/6ef160c3133a78de015830860197602ca1c855d3/java-objc-bridge-1.0.0.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.google.code.findbugs/jsr305/3.0.1/f7be08ec23c21485b9b5a1cf1654c2ec8c58168d/jsr305-3.0.1.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.ibm.icu/icu4j-core-mojang/51.2/63d216a9311cca6be337c1e458e587f99d382b84/icu4j-core-mojang-51.2.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.mojang/authlib/1.5.25/9834cdf236c22e84b946bba989e2f94ef5897c3c/authlib-1.5.25.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.mojang/patchy/1.1/aef610b34a1be37fa851825f12372b78424d8903/patchy-1.1.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.mojang/realms/1.10.17/e6a623bf93a230b503b0e3ae18c196fcd5aa3299/realms-1.10.17.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.mojang/text2speech/1.10.3/48fd510879dff266c3815947de66e3d4809f8668/text2speech-1.10.3.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/commons-codec/commons-codec/1.10/4b95f4897fa13f2cd904aee711aeafc0c5295cd8/commons-codec-1.10.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/commons-io/commons-io/2.5/2852e6e05fbb95076fc091f6d1780f1f8fe35e0f/commons-io-2.5.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/commons-logging/commons-logging/1.1.3/f6f66e966c70a83ffbdb6f17a0919eaf7c8aca7f/commons-logging-1.1.3.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/io.netty/netty-all/4.1.9.Final/97860965d6a0a6b98e7f569f3f966727b8db75/netty-all-4.1.9.Final.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/it.unimi.dsi/fastutil/7.1.0/9835253257524c1be7ab50c057aa2d418fb72082/fastutil-7.1.0.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/net.java.dev.jna/jna/4.4.0/cb208278274bf12ebdb56c61bd7407e6f774d65a/jna-4.4.0.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/net.java.dev.jna/platform/3.4.0/e3f70017be8100d3d6923f50b3d2ee17714e9c13/platform-3.4.0.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/net.java.jinput/jinput/2.0.5/39c7796b469a600f72380316f6b1f11db6c2c7c4/jinput-2.0.5.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/net.java.jutils/jutils/1.0.0/e12fe1fda814bd348c1579329c86943d2cd3c6a6/jutils-1.0.0.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/net.sf.jopt-simple/jopt-simple/5.0.3/cdd846cfc4e0f7eefafc02c0f5dce32b9303aa2a/jopt-simple-5.0.3.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.apache.commons/commons-compress/1.8.1/a698750c16740fd5b3871425f4cb3bbaa87f529d/commons-compress-1.8.1.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.apache.commons/commons-lang3/3.5/6c6c702c89bfff3cd9e80b04d668c5e190d588c6/commons-lang3-3.5.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.apache.httpcomponents/httpclient/4.3.3/18f4247ff4572a074444572cee34647c43e7c9c7/httpclient-4.3.3.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.apache.httpcomponents/httpcore/4.3.2/31fbbff1ddbf98f3aa7377c94d33b0447c646b6e/httpcore-4.3.2.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.apache.logging.log4j/log4j-api/2.8.1/e801d13612e22cad62a3f4f3fe7fdbe6334a8e72/log4j-api-2.8.1.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.apache.logging.log4j/log4j-core/2.8.1/4ac28ff2f1ddf05dae3043a190451e8c46b73c31/log4j-core-2.8.1.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.lwjgl.lwjgl/lwjgl/2.9.2-nightly-20140822/7707204c9ffa5d91662de95f0a224e2f721b22af/lwjgl-2.9.2-nightly-20140822.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/org.lwjgl.lwjgl/lwjgl_util/2.9.2-nightly-20140822/f0e612c840a7639c1f77f68d72a28dae2f0c8490/lwjgl_util-2.9.2-nightly-20140822.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/oshi-project/oshi-core/1.1/9ddf7b048a8d701be231c0f4f95fd986198fd2d8/oshi-core-1.1.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.google.code.gson/gson/2.8.0/c4ba5371a29ac9b2ad6129b1d39ea38750043eff/gson-2.8.0.jar
		forge-1.12-14.21.1.2387-mdk/gradle.cache/caches/modules-2/files-2.1/com.google.guava/guava/21.0/3a3d111be1be1b745edfa7d91678a12d7ed38709/guava-21.0.jar
	)
	#for LIB in "${FOUND_LIBS[@]}"; do echo "${LIB}"; done

	CLASSPATH=`echo ${FOUND_LIBS[@]} | sed 's/forge-'$FORGE_VERSION'-mdk\/gradle.cache\/caches\/modules-2\/files-2.1/$LIB/g' | tr ' ' ':'`
	#CLASSPATH=`find forge-$FORGE_VERSION-mdk/gradle.cache/caches/modules-2/files-2.1 -type f -name "*.jar" -print0 | sed 's/forge-'$FORGE_VERSION'-mdk\/gradle.cache\/caches\/modules-2\/files-2.1/$LIB/g' | tr '\000' ':'`

	echo -n 'java -Xms1G -Xmx1G' '-Djava.library.path="'\$MiM'/libs"' '-classpath "'$CLASSPATH':$MiM/forge-'$FORGE_VERSION'-mdk/'$FORGE_SNAPSHOT'/forgeSrc-'$FORGE_VERSION'.jar:$MiM/mim-'$SIDE'stream.jar" ' >> ./$SIDE'stream.sh'
	if [[ $SIDE = "down" ]]; then
		echo -n 'se.mitm.server.DedicatedServerProxy' >> ./$SIDE'stream.sh'
	else
		echo -n 'se.mitm.client.MinecraftClientProxy' >> ./$SIDE'stream.sh'
	fi
	# https://unix.stackexchange.com/questions/108635/why-i-cant-escape-spaces-on-a-bash-script/108663#108663
	echo ' "$@"' >> ./$SIDE'stream.sh'

	chmod +x ./$SIDE'stream.sh'

	echo 'echo "java -classpath mim-'$SIDE'stream.jar" >> ./'$SIDE'stream.sh'
}

#--------------------------------------------------------------------------------------------------------------------------------

upgrade()
{
	exit

	if [ -d "$MIM_DIR" ]; then
		cd "$MIM_DIR"/ || error_exit
	else
		[ -d ./$MCP_DIR/bin/minecraft ] || error_msg 'Target directory ['$MIM_DIR'] not found'
	fi

	for SIDE in "down" "up"
	do
		if [ -f ./mim-$SIDE'stream.jar' ]; then
			INST_VERSION=`java -classpath mim-$SIDE'stream.jar' se.mitm.version.Version | sed 's/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/'`
			#INST_MAJOR=`echo $INST_VERSION | sed 's/^v\([0-9]*\).*$/\1/'`
			#INST_MINOR=`echo $INST_VERSION | sed 's/^v[0-9]*\.\([0-9]*\)-.*$/\1/'`

			NET_VERSION=`curl -sfL $NET_DOWNLOAD/mim-$SIDE'stream'/Version.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/'`
			#NET_MAJOR=`echo $NET_VERSION | sed 's/^v\([0-9]*\).*$/\1/'`
			#NET_MINOR=`echo $NET_VERSION | sed 's/^v[0-9]*\.\([0-9]*\)-.*$/\1/'`

			#echo $INST_VERSION - $NET_VERSION - $INST_MAJOR $INST_MINOR - $NET_MAJOR $NET_MINOR
			#if [ "$INST_MAJOR" -lt "$NET_MAJOR" ]; then
			if [ "$INST_VERSION" != "$NET_VERSION" ]; then
				download_mim || { echo "FAIL!"; continue; }
				echo $SIDE"stream: "`java -classpath mim-$SIDE'stream.jar' se.mitm.version.Version`
				generate_run_script
			else
				echo "== MiM ["$SIDE"stream] component =="
				INST_VERSION=`java -classpath mim-$SIDE'stream.jar' se.mitm.version.Version | sed 's/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/'`
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
# Oracle reports "java version". OpenJDK reports "openjdk version".
JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^.*version \"\(.*\)\".*$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
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

#if [[ $UPGRADE == 1 ]]; then
#	upgrade || error_exit
#fi

create_working_directory || error_exit
cd "$MIM_DIR"/ || error_exit

compile_jzmq_lib || error_exit
download_mcp || error_exit
download_forge || error_exit
prep_forge || error_exit
download_mim || error_exit 
generate_run_script || error_exit

cd ..

#--------------------------------------------------------------------------------------------------------------------------------

echo "SUCCESS!"; exit 0
