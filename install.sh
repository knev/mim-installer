#!/bin/bash

pause() {
	read -n 1 -p "Press [KEY] to continue ..."
	echo
}

usage() {
	echo "usage: $0 [-d|--directory DIRECTORY] [--clean]"
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

#TODO: use /proc/version or uname -v instead to find linux version?
# https://en.wikipedia.org/wiki/Uname
#
UNAME="$(uname -s)"
case "${UNAME}" in
	Linux*)		ARCH=linux;;
	Darwin*)	ARCH=osx;;
#	CYGWIN*)	ARCH=Cygwin;;
#	MINGW*)		ARCH=MinGw;;
#	*)			ARCH="UNKNOWN:${unameOut}"
	*)			error_msg "unsupported architecture: [$UNAME]"
esac

# http://linuxcommand.org/lc3_wss0120.php
#
DIRECTORY=""
DOWNSTREAM=0
UPSTREAM=0
FORGE_VERSION=1.12-14.21.1.2387
FORGE_SNAPSHOT=gradle.cache/caches/minecraft/net/minecraftforge/forge/$FORGE_VERSION/snapshot/20170624
CLEAN=0
while [ ! -z "$1" ]; do
	case $1 in
		-d | --directory )		shift
								DIRECTORY=$1
								;;
		--downstream )			DOWNSTREAM=1
								;;
		--upstream )			UPSTREAM=1
								;;
		--clean )				CLEAN=1
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

INST_VERSION=7

# (23) Failed writing body: 
# https://stackoverflow.com/questions/16703647/why-does-curl-return-error-23-failed-writing-body
# This happens when a piped program (e.g. grep) closes the read pipe before the previous program is finished writing the whole page.
# ... as soon as grep has what it wants it will close the read stream from curl.
# 
NET_INST_URL=https://raw.githubusercontent.com/knev/mim-installer/master/install.sh
NET_INST_VERSION=`curl -sfL --url $NET_INST_URL 2>/dev/null | sed -nE '/INST_VERSION=[0-9]+/p' | sed 's/^INST_VERSION=\(.*\)$/\1/'  `

if [ -z "$NET_INST_VERSION" ]; then
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

MIM_DIR=MiM
SIDE="down"
#(( $DOWNSTREAM )) && { MIM_DIR=MiM; SIDE="down"; } Default !
(( $UPSTREAM )) && { MIM_DIR=MiM-upstream; SIDE="up"; }

create_working_directory() 
{
#	if [ -f "$MIM_DIR"/forge-$FORGE_VERSION-mdk/$FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION.jar ]; then
#		read -s -n 1 -p 'Target directory ['$MIM_DIR'] exists, overwrite? [N/y] ' INPUT || error_exit
#		RES=$( tr '[:upper:]' '[:lower:]' <<<"$INPUT" )
#		if [[ "$RES" != "y" ]]; then
#			echo $'\n'"Abort."
#			exit 0
#		fi
#		echo
#	fi

	if [ $DIRECTORY ]; then
		MIM_DIR=$DIRECTORY
	else
		[[ -f ./mim-upstream.jar || -f ./mim-downstream.jar ]] && { MIM_DIR="."; echo "Installation found in \$PWD, using ['$MIM_DIR'] as target ..."; }
	fi

	# -----

	if (( ! $CLEAN )); then
		(( ! $UPSTREAM )) && [[ -f "$MIM_DIR"/mim-downstream.jar ]] && { echo "Set up target directory :: SKIPPED"; echo "Upgrading ..."; return 0; } # redundant SIDE="down" 
		(( ! $DOWNSTREAM )) && [[ -f "$MIM_DIR"/mim-upstream.jar ]] && { echo "Set up target directory :: SKIPPED"; echo "Upgrading ..."; SIDE="up"; return 0; }
	fi

	# -----

	echo 'Setting up target directory: ['$MIM_DIR'] ...'
	mkdir -p "$MIM_DIR" || error_msg 'failed to make target directory: ['$MIM_DIR']'
}

#--------------------------------------------------------------------------------------------------------------------------------

NET_DOWNLOAD=https://mitm.se/mim-install # curl has -L switch, so should be ok to leave off the www

check_latest_mim_version()
{
	NET_VERSION=`curl -sfL $NET_DOWNLOAD/Version-mim-$SIDE'stream'.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/'`
	NET_SHORT_VERSION=`echo $NET_VERSION | sed -nE '/^v[0-9]+.[0-9]+-[0-9]+-.*$/p' | sed 's/^\(v[0-9]*\.[0-9]*-[0-9]*\)-.*$/\1/'`

	[ -z "$NET_SHORT_VERSION" ] && error_msg "Unable to determine the latest version of MiM"

	return 0; #TODO: required because something before sets the error
}

#--------------------------------------------------------------------------------------------------------------------------------

compile_jzmq_lib()
{
	if (( ! $CLEAN )); then
		[ -f libs/libjzmq.a ] && { echo "Compile Java binding for zmq :: SKIPPED"; return 0; }
	fi 

	# -----

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

download_forge()
{
	[ -d mcp940 ] && { rm -rf mcp940 || error_exit; }

	# -----

	if (( ! $CLEAN )); then
		[ -d forge-$FORGE_VERSION-mdk ] && { echo "Download Forge for Minecraft :: SKIPPED"; return 0; }
	fi

	# -----

	echo == Downloading Forge for Minecraft ==
	[ -d forge-$FORGE_VERSION-mdk ] && { rm -rf forge-$FORGE_VERSION-mdk || error_exit; }
	mkdir -p forge-$FORGE_VERSION-mdk || error_msg "failed to make target directory: [forge-$FORGE_VERSION-mdk]"
	curl -f -o forge-$FORGE_VERSION-mdk.zip -L https://files.minecraftforge.net/maven/net/minecraftforge/forge/$FORGE_VERSION/forge-$FORGE_VERSION-mdk.zip || error_exit
	unzip -qo -d forge-$FORGE_VERSION-mdk/. forge-$FORGE_VERSION-mdk.zip || error_exit

	rm forge-$FORGE_VERSION-mdk.zip
}

#--------------------------------------------------------------------------------------------------------------------------------

prep_forge()
{
	if (( ! $CLEAN )); then
		[ -f forge-$FORGE_VERSION-mdk/$FORGE_SNAPSHOT/forgeSrc-$FORGE_VERSION.jar ] && { echo "Preparing Minecraft sources :: SKIPPED"; return 0; }
	fi

	# -----

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
	curl -f -o ./$BROKEN_PACKETS_NO_LWJGL -L $NET_DOWNLOAD/$NET_SHORT_VERSION/$BROKEN_PACKETS_NO_LWJGL || error_exit
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
	if (( ! $CLEAN )); then
		if [ -f ./mim-$SIDE'stream.jar' ]; then
			INST=( `java -classpath mim-$SIDE'stream.jar' se.mitm.version.Version 2>&1 | grep -m1 "Man in the Middle of Minecraft (MiM)" | sed 's/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/' | sed 's/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)-.*$/\1 \2 \3/'` )
			NET=( `curl -sfL https://mitm.se/mim-install/Version-mim-$SIDE'stream.java' | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/' | sed 's/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)-.*$/\1 \2 \3/'` )
			UPGRADE=0; for NR in 0 1 2; do [ ${INST[$NR]} -lt ${NET[$NR]} ] && UPGRADE=1; done

			(( ! $UPGRADE )) && { echo "Download MiM-"$SIDE"stream component :: SKIPPED"; return 0; }

			echo "MiM-downstream-v"${INST[0]}.${INST[1]}-${INST[2]}" installed, latest [v"${NET[0]}.${NET[1]}-${NET[2]}"], upgrading ..."
		fi
	fi

	# -----

	echo "== Downloading MiM ["$SIDE"stream] component =="
	[ -f ./mim-$SIDE'stream.jar' ] && { mv ./mim-$SIDE'stream.jar' ./mim-$SIDE'stream.jar~' || return 1; }
	curl -f -o ./mim-$SIDE'stream.jar.tmp' -L $NET_DOWNLOAD/$NET_SHORT_VERSION/mim-$SIDE'stream.jar' || return 1
	mv ./mim-$SIDE'stream.jar.tmp' ./mim-$SIDE'stream.jar' || retun 1
	echo $SIDE"stream: "`java -classpath mim-$SIDE'stream.jar' se.mitm.version.Version`
}

#--------------------------------------------------------------------------------------------------------------------------------

generate_run_script() 
{

	if [ $SIDE == "up" ]; then
		[ -f upstream.sh ] && { mv upstream.sh mim-upstream.sh~ || error_exit; }
		[ -f proxy.properties ] && { mv proxy.properties mim-upstream.properties || error_exit; }
	else
		[ -f downstream.sh ] && { mv downstream.sh mim.sh~ || error_exit; }
	fi

	# -----

	#if (( ! $CLEAN )); then
	#fi

	# -----

	OUT=mim.sh
	[ $SIDE == "up" ] && OUT=mim-upstream.sh
	
	echo "== Generating ["$SIDE"stream] run script =="
	[ -f $OUT ] && { mv $OUT $OUT'~' || return 1; }
	# https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n
	echo '#!/bin/bash' > $OUT
	echo 'ARGS=$@'$'\n' >> $OUT

	#
	# basically don't have to have to escape anything except for single quotes, which can not occur inside single quotes
	# https://unix.stackexchange.com/questions/187651/how-to-echo-single-quote-when-using-single-quote-to-wrap-special-characters-in
	# http://tldp.org/LDP/Bash-Beginners-Guide/html/sect_07_01.html
	#

	# [ -f mim-downstream.jar ] || { echo "File [mim-downstream.jar] not found. Abort."; exit 1; }
	#
	echo '[ -f mim-'$SIDE'stream.jar ] || { echo "File [mim-'$SIDE'stream.jar] not found. Abort."; exit 1; }'$'\n' >> $OUT

	# while [ ! -z "$1" ]; do [ "$1" == "--version" ] && { echo `java -classpath mim-upstream.jar se.mitm.version.Version`; exit 0; }; shift; done
	#
	echo 'while [ ! -z "$1" ]; do [ "$1" == "--version" ] && { echo `java -classpath mim-'$SIDE'stream.jar se.mitm.version.Version`; exit 0; }; shift; done'$'\n' >> $OUT
	
	# INST=( `java -classpath mim-downstream.jar se.mitm.version.Version 2>&1 | grep -m1 "Man in the Middle of Minecraft (MiM)" | sed 's/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/' | sed 's/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)-.*$/\1 \2 \3/'` )
	# NET=( `curl -sfL https://mitm.se/mim-install/Version-mim-downstream.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/' | sed 's/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)-.*$/\1 \2 \3/'` )
	# for NR in 0 1 2; do [ ${INST[$NR]} -lt ${NET[$NR]} ] && { echo "downstream-v"${INST[0]}.${INST[1]}-${INST[2]}" installed, latest [v"${NET[0]}.${NET[1]}-${NET[2]}"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; break; }; done
	#
	echo 'INST=( `java -classpath mim-'$SIDE'stream.jar se.mitm.version.Version 2>&1 | grep -m1 "Man in the Middle of Minecraft (MiM)" | sed '\''s/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/'\'' | sed '\''s/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)-.*$/\1 \2 \3/'\''` )' >> $OUT
	echo 'NET=( `curl -sfL https://mitm.se/mim-install/Version-mim-'$SIDE'stream.java | grep -m1 commit | sed '\''s/.*commit=[ ]*\"\([^"]*\)\";/\1/'\'' | sed '\''s/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)-.*$/\1 \2 \3/'\''` )' >> $OUT
	echo 'for NR in 0 1 2; do [ ${INST[$NR]} -lt ${NET[$NR]} ] && { echo "MiM-'$SIDE'stream-v"${INST[0]}.${INST[1]}-${INST[2]}" installed, latest [v"${NET[0]}.${NET[1]}-${NET[2]}"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; break; }; done'$'\n' >> $OUT

	# VARIABLES to shorten classpath
	#
	echo 'MiM="'`pwd`'"' >> ./$OUT
	echo '[ -d "$MiM" ] || echo "Error: Invalid target directory "$MiM' >> $OUT
	echo 'LIB=$MiM/forge-'$FORGE_VERSION'-mdk/gradle.cache/caches/modules-2/files-2.1'$'\n' >> ./$OUT

	if [[ $ARCH == osx ]]; then
		# export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
		# JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^java version \"\(.*\)\".*$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
		# [ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; } 

		#TODO: just use $JAVA_HOME here? instead of reading it again?
		echo 'export JAVA_HOME=`/usr/libexec/java_home -v 1.8`' >> $OUT
		echo 'JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed '\''s/^.*version \"\(.*\)\".*$/\1/'\'' | sed '\''s/\([0-9].[0-9]\).*/\1/'\''`' >> $OUT
		echo '[ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $OUT

	elif [[ $ARCH == linux ]]; then
		echo 'export JAVA_HOME="'$JAVA_HOME'"' >> $OUT
		echo '[ -n "JAVA_HOME" ] && export PATH=$JAVA_HOME/bin:$PATH' >> $OUT
		echo 'JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed '\''s/^.*version \"\(.*\)\".*$/\1/'\'' | sed '\''s/\([0-9].[0-9]\).*/\1/'\''`' >> $OUT
		echo '[ "$JAVA_VERSION" == "1.8" ] || { echo "Java JDK version 1.8 not found; unsupported environment ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $OUT

	fi

	echo "Gathering libraries ..."

	declare -a REQUIRED_LIBS=(
		"1|ca.weblite\/java-objc-bridge\/.*\.jar"
		"1|com.google.code.findbugs\/jsr305\/.*\.jar"
		"1|com.google.code.gson\/gson\/2.8.0\/.*\.jar"
		"1|com.google.guava\/guava\/21.0\/.*\.jar"
		"1|com.ibm.icu\/icu4j-core-mojang\/.*\.jar"
		"1|com.mojang\/authlib\/.*\.jar"
		"1|com.mojang\/patchy\/.*\.jar"
		"1|com.mojang\/realms\/.*\.jar"
		"1|com.mojang\/text2speech\/.*\.jar"
		"1|com.paulscode\/codecjorbis\/.*\.jar"
		"1|com.paulscode\/codecwav\/.*\.jar"
		"1|com.paulscode\/libraryjavasound\/.*\.jar"
		"1|com.paulscode\/librarylwjglopenal\/.*\.jar"
		"1|com.paulscode\/soundsystem\/.*\.jar"
		"1|commons-codec\/commons-codec\/1.10\/.*\.jar"
		"1|commons-io\/commons-io\/2.5\/.*\.jar"
		"1|commons-logging\/commons-logging\/.*\.jar"
		"1|io.netty\/netty-all\/.*\.jar"
		"1|it.unimi.dsi\/fastutil\/.*\.jar"
		"1|net.java.dev.jna\/jna\/.*\.jar"
		"1|net.java.dev.jna\/platform\/.*\.jar"
		"1|net.java.jinput\/jinput\/.*\.jar"
		"1|net.java.jinput\/jinput-platform\/.*$ARCH\.jar"
		"1|net.java.jutils\/jutils\/.*\.jar"
		"1|net.sf.jopt-simple\/jopt-simple\/.*\.jar"
		"1|org.apache.commons\/commons-compress\/.*\.jar"
		"1|org.apache.commons\/commons-lang3\/.*\.jar"
		"1|org.apache.httpcomponents\/httpclient\/.*\.jar"
		"1|org.apache.httpcomponents\/httpcore\/.*\.jar"
		"1|org.apache.logging.log4j\/log4j-api\/.*\.jar"
		"1|org.apache.logging.log4j\/log4j-core\/.*\.jar"
		"1|org.lwjgl.lwjgl\/lwjgl\/.*\.jar"
		"1|org.lwjgl.lwjgl\/lwjgl_util\/.*\.jar"
		"1|org.lwjgl.lwjgl\/lwjgl-platform\/.*$ARCH\.jar"
		"1|oshi-project\/oshi-core\/.*\.jar"
	)
	declare -a FOUND_LIBS=(`find forge-$FORGE_VERSION-mdk/gradle.cache/caches/modules-2/files-2.1 -type f -name "*.jar" `)

	declare -a CLASSPATH=()
	for REQ in ${REQUIRED_LIBS[@]}
	do 
		NR=${REQ%|*}
		PATTERN=${REQ/[0-9]|/}
		FOUND=( `echo ${FOUND_LIBS[@]} | tr ' ' ':' | perl -F":" -ane 'foreach (@F) { print "$_\n" if /^forge-'$FORGE_VERSION'-mdk\/gradle.cache\/caches\/modules-2\/files-2.1\/'$PATTERN'$/; }'` )
		for JAR in ${FOUND[@]}; do echo $JAR; done
		if (( ! ${#FOUND[@]} )); then
			echo "WARNING: required library ["$( echo $PATTERN | tr -d '\\' )"] not found!"
		elif (( ${#FOUND[@]} != $NR )); then
			echo "WARNING: duplicates found for library [$PATTERN]!"
		fi
		CLASSPATH=( ${CLASSPATH[@]} ${FOUND[@]} )
	done
	echo "DONE!"

	CLASSPATH=`echo ${CLASSPATH[@]} | sed 's/forge-'$FORGE_VERSION'-mdk\/gradle.cache\/caches\/modules-2\/files-2.1/$LIB/g' | tr ' ' ':'`
	#CLASSPATH=`find forge-$FORGE_VERSION-mdk/gradle.cache/caches/modules-2/files-2.1 -type f -name "*.jar" -print0 | sed 's/forge-'$FORGE_VERSION'-mdk\/gradle.cache\/caches\/modules-2\/files-2.1/$LIB/g' | tr '\000' ':'`

	echo -n 'java -Xms1G -Xmx1G' '-Djava.library.path="'\$MiM'/libs"' '-classpath "'$CLASSPATH':$MiM/forge-'$FORGE_VERSION'-mdk/'$FORGE_SNAPSHOT'/forgeSrc-'$FORGE_VERSION'.jar:$MiM/mim-'$SIDE'stream.jar" ' >> ./$OUT
	if [[ $SIDE = "down" ]]; then
		echo -n 'se.mitm.server.DedicatedServerProxy' >> ./$OUT
	else
		echo -n 'se.mitm.client.MinecraftClientProxy' >> ./$OUT
	fi
	# https://unix.stackexchange.com/questions/108635/why-i-cant-escape-spaces-on-a-bash-script/108663#108663
	echo ' $ARGS' >> ./$OUT

	chmod +x ./$OUT

	echo '"java -classpath mim-'$SIDE'stream.jar" >> ./'$OUT
}

#--------------------------------------------------------------------------------------------------------------------------------

REQ=java; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
REQ=javac; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
#REQ=jar; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"

check_java_version()
{
	echo 'JAVA_HOME='$JAVA_HOME'; '`java -version 2>&1 | head -n 1`
	# Oracle reports "java version". OpenJDK reports "openjdk version".
	JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^.*version \"\(.*\)\".*$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
	[ "$JAVA_VERSION" == "1.8" ]
}

if [[ $ARCH == osx ]]; then
	# https://stackoverflow.com/questions/21964709/how-to-set-or-change-the-default-java-jdk-version-on-os-x
	export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
	check_java_version || { echo JAVA_HOME is determined by \"/usr/libexec/java_home\"; error_msg "This install script requires Java JDK version 1.8"; }
elif [[ $ARCH == linux ]]; then
	# https://stackoverflow.com/questions/41059994/default-java-java-home-vs-sudo-update-alternatives-config-java
	# https://unix.stackexchange.com/questions/212139/how-to-switch-java-environment-for-specific-process
	[ -n "JAVA_HOME" ] && export PATH=$JAVA_HOME/bin:$PATH
	if ! check_java_version; then
		echo 'JAVA_HOME should point to the JDK root e.g., export JAVA_HOME="/usr/lib/jvm/openjdk-8-jdk"'
		error_msg "This install script requires Java JDK version 1.8"
	fi
else
	error_msg "Unknown Java JDK support for architecture: [$UNAME]"
fi

REQ=g++; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=git; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=automake; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=make; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=pkg-config
REQ=autoconf
REQ=curl; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"
REQ=unzip; which $REQ > /dev/null || error_msg "This install script requires [$REQ] to be installed"

REQ=libtool # (a mac version is preinstalled)
if [[ $ARCH == osx ]]; then
	which glibtool > /dev/null || error_msg "This install script requires [libtool] to be installed"
fi

#TODO host:/usr/local/opt/zmq$ [ -f include/zmq.h ] || echo "NO"
if [[ $ARCH = osx ]]; then
	REQ=zmq # ./configure will fail if not installed
elif [[ $ARCH = linux ]]; then
	REQ=libzmq3-dev # ./configure will fail if not installed
fi

#--------------------------------------------------------------------------------------------------------------------------------

create_working_directory || error_exit
check_latest_mim_version || error_exit
cd "$MIM_DIR"/ || error_exit

compile_jzmq_lib || error_exit
download_forge || error_exit
prep_forge || error_exit
download_mim || error_exit 
generate_run_script || error_exit

cd ..

#--------------------------------------------------------------------------------------------------------------------------------

echo "SUCCESS!"; exit 0
