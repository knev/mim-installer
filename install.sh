#!/bin/bash

pause() {
	read -n 1 -p "Press [KEY] to continue ..."
	echo
}

usage() {
	echo "usage: $0 [-d|--directory DIRECTORY] [--docker] [--local-upstream] [--clean] [-h|--help]"
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

# set -x

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
LOCAL=0
FORGE_VERSION=1.14.4-28.2.0
#SNAPSHOT_VERSION=20170624
#FORGE_SNAPSHOT=gradle.cache/caches/minecraft/net/minecraftforge/forge/$FORGE_VERSION/snapshot/$SNAPSHOT_VERSION
FORGE_SNAPSHOT=gradle.cache/caches/forge_gradle/mcp_repo/de/oceanlabs/mcp/mcp_config/1.14.4-20190829.143755/joined
CLEAN=0
DEV=0
DOCKER=0
REQ_VERSION=""
while [ ! -z "$1" ]; do
	case $1 in
		-d | --directory )		shift
								DIRECTORY=$1
								;;
		--downstream )			DOWNSTREAM=1
								;;
		--upstream )			UPSTREAM=1
								;;
		--local )				LOCAL=1
								;;
		--local-upstream )		UPSTREAM=1
								LOCAL=1
								;;
		--upgrade )				CLEAN=0;
								;;
		--clean )				CLEAN=1
								;;
		--dev )					DEV=1
								;;
		--docker )				DOCKER=1
								;;
		--req-version )			shift
								REQ_VERSION=$1
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

INST_VERSION=10

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
(( $UPSTREAM )) && SIDE="up"
(( $UPSTREAM )) && (( !$LOCAL )) && MIM_DIR=MiM-upstream

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
		if (( $UPSTREAM )); then
			[[ -f "$MIM_DIR"/mim-upstream.jar ]] && { echo "Set up target directory ['$MIM_DIR'] :: SKIPPED"; echo "Upgrading ..."; return 0; } # redundant SIDE="up"
		else
			(( $LOCAL )) && [[ -f "$MIM_DIR"/mim-upstream.jar ]] && { echo "Set up target directory ['$MIM_DIR'] :: SKIPPED"; echo "Upgrading ..."; SIDE="up"; return 0; }
			[[ -f "$MIM_DIR"/mim-downstream.jar ]] && { echo "Set up target directory ['$MIM_DIR'] :: SKIPPED"; echo "Upgrading ..."; return 0; } # redundant SIDE="down" 
		fi
	fi

	# -----

	echo 'Setting up target directory: ['$MIM_DIR'] ...'
	mkdir -p "$MIM_DIR" || error_msg 'failed to make target directory: ['$MIM_DIR']'
}

#--------------------------------------------------------------------------------------------------------------------------------

DOCKER_MIM_DIR=MiM
(( $UPSTREAM )) && DOCKER_MIM_DIR=MiM-upstream
DOCKER_IMAGE=`echo $DOCKER_MIM_DIR | tr '[:upper:]' '[:lower:]'`

docker_build_image()
{
	REQ=docker; which $REQ > /dev/null || error_msg "please install the Docker, [$REQ] not found"
	REQ=docker-compose; which $REQ > /dev/null || error_msg "please install the Docker, [$REQ] not found"

	DOCKER_CONTEXT=docker

	if (( $CLEAN )); then
		docker rmi -f $DOCKER_IMAGE
	else
		docker inspect --type=image $DOCKER_IMAGE >/dev/null && { echo "Building Docker image :: SKIPPED"; return 0; }
	fi

	echo '== Building Docker image =='
	mkdir -p $DOCKER_CONTEXT
	curl -f --silent -o $DOCKER_CONTEXT/Dockerfile -L https://raw.githubusercontent.com/knev/mim-installer/master/Dockerfile-$DOCKER_IMAGE
	docker build -t $DOCKER_IMAGE $DOCKER_CONTEXT
}

docker_cp()
{
	if (( ! $CLEAN )); then
		[ -f $DOCKER_IMAGE.sh ] && { echo "Extracting runtime to writeable volume :: SKIPPED"; return 0; }
	fi

	echo '== Extracting runtime to writeable volume ==' 
	#https://stackoverflow.com/questions/25292198/docker-how-can-i-copy-a-file-from-an-image-to-a-host
	DOCKER_CONTAINER=`docker create $DOCKER_IMAGE`

	if [ ! -f forge-$FORGE_VERSION-mdk/$FORGE_SNAPSHOT/rename.jar ]; then
		docker cp $DOCKER_CONTAINER:/home/mitm/$DOCKER_MIM_DIR/forge-$FORGE_VERSION-mdk .
	fi
	docker cp $DOCKER_CONTAINER:/home/mitm/$DOCKER_MIM_DIR/mim-$SIDE'stream.jar' .
	docker cp $DOCKER_CONTAINER:/home/mitm/$DOCKER_MIM_DIR/$DOCKER_IMAGE.sh .
	if [ $SIDE == "down" ]; then 
		docker cp $DOCKER_CONTAINER:/home/mitm/$DOCKER_MIM_DIR/mim-upstream.jar .
		docker cp $DOCKER_CONTAINER:/home/mitm/$DOCKER_MIM_DIR/mim-upstream-local.sh .
		docker cp $DOCKER_CONTAINER:/home/mitm/$DOCKER_MIM_DIR/mim-upstream.properties .
	fi

	if [[ $ARCH = linux ]]; then
		DOCKER_USER_GROUP=docker

		DOCKER_GROUP=`less /etc/group | cut -d: -f1 | grep $DOCKER_USER_GROUP`
		[[ -n $DOCKER_GROUP ]] || error_msg "the ['$DOCKER_USER_GROUP'] user group doesn't exist, but is required under linux"

		USER_DOCKER=`groups | sed -nE '/'$DOCKER_USER_GROUP'/p'`
		[[ -n $USER_DOCKER ]] || error_msg "you are currenly not a member of the ['$DOCKER_USER_GROUP'] user group"

		chown -R :$DOCKER_USER_GROUP .

		chmod -R g+w .
	fi
}

generate_docker_compose()
{
	OUT=docker-compose.yml
	[ -f $OUT ] && { mv $OUT $OUT'~' || return 1; }

	echo '== Writing ['$OUT'] for ['$DOCKER_MIM_DIR'] =='

	MIM_PORT=25511
	[ $SIDE == "up" ] && MIM_PORT=4999

# use version 2.2, because 2.4 freaks out under Ubuntu
# https://unix.stackexchange.com/questions/77277/how-to-append-multiple-lines-to-a-file
#----------------
cat << EOF > $OUT
version: "2.2"
networks:
  local_net:
    driver: bridge
services:
  $DOCKER_IMAGE:
    image: $DOCKER_IMAGE
    container_name: $DOCKER_IMAGE
    networks:
      - local_net
    ports:
      - "$MIM_PORT:$MIM_PORT"
    volumes:
      - "$PWD:/home/mitm/$DOCKER_MIM_DIR"
EOF
#----------------
	
	if [ $SIDE == "down" ]; then
		if [[ $ARCH = osx ]]; then
			MINECRAFT_HOME=`echo ~/Library/Application Support/minecraft`
		elif [[ $ARCH = linux ]]; then
			MINECRAFT_HOME=`echo ~/.minecraft`
		fi
		
		[[ -d "$MINECRAFT_HOME" ]] || error_msg "Can not find the Minecraft folder at [$MINECRAFT_HOME]"

		[ -f mim-upstream.properties ] && { mv mim-upstream.properties mim-upstream.properties~; sed 's/^addr=0.0.0.0/addr=local-upstream/' < mim-upstream.properties~ >mim-upstream.properties; }

#----------------
cat << EOF >> $OUT
      - "$MINECRAFT_HOME:/home/mitm/.minecraft"
    command: --local-addr=local-upstream
  local-upstream:
    image: mim
    container_name: local-upstream
    networks:
      - local_net
    ports:
      - "4499:4499"
    volumes:
      - "$PWD:/home/mitm/$DOCKER_MIM_DIR"
    entrypoint: ["./mim-upstream-local.sh"]
EOF
#----------------
	fi

	echo '"services: '$DOCKER_IMAGE': ... " >> ./'$OUT
exit
}

#--------------------------------------------------------------------------------------------------------------------------------

check_java_version()
{
	echo 'JAVA_HOME='$JAVA_HOME'; '`java -version 2>&1 | head -n 1`
	# Oracle reports "java version". OpenJDK reports "openjdk version".
	JAVA_VERSION=`java -version 2>&1 | head -n 1 | sed 's/^.*version \"\(.*\)\".*$/\1/' | sed 's/\([0-9].[0-9]\).*/\1/'`
	[ "$JAVA_VERSION" == "1.8" ]
}

check_pre_reqs()
{
	REQ=java; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
	REQ=javac; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"
	REQ=jar; which $REQ > /dev/null || error_msg "please install the Java JDK, [$REQ] not found"

	if [[ $ARCH == osx ]]; then
		# https://stackoverflow.com/questions/21964709/how-to-set-or-change-the-default-java-jdk-version-on-os-x
		export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
		check_java_version || { echo JAVA_HOME is determined by \"/usr/libexec/java_home\"; error_msg "This install script requires Java JDK version 1.8"; }
	elif [[ $ARCH == linux ]]; then
		# https://stackoverflow.com/questions/41059994/default-java-java-home-vs-sudo-update-alternatives-config-java
		# https://unix.stackexchange.com/questions/212139/how-to-switch-java-environment-for-specific-process
		[ -n "JAVA_HOME" ] && export PATH=$JAVA_HOME/bin:$PATH
		if ! check_java_version; then
			if [[ -f "$MIM_DIR"/$OUT ]]; then
				echo "Java JDK version 1.8 check FAILED, adopting JAVA_HOME from ['$OUT']"
				JAVA_HOME=`cat "$MIM_DIR"/$OUT | sed -nE '/^export JAVA_HOME=/p' | sed 's/^export JAVA_HOME="\(.*\)"/\1/' `
				[ -n "JAVA_HOME" ] && export PATH=$JAVA_HOME/bin:$PATH
				if ! check_java_version; then
					echo 'JAVA_HOME should point to the JDK root e.g., export JAVA_HOME="/usr/lib/jvm/openjdk-8-jdk"'
					error_msg "This install script requires Java JDK version 1.8"
				fi
			else
				echo 'JAVA_HOME should point to the JDK root e.g., export JAVA_HOME="/usr/lib/jvm/openjdk-8-jdk"'
				error_msg "This install script requires Java JDK version 1.8"
			fi
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
}

#--------------------------------------------------------------------------------------------------------------------------------

JAR_VERSION=""
NET_VERSION=""
NET_DOWNLOAD=https://mitm.se/mim-install # curl has -L switch, so should be ok to leave off the www

check_latest_mim_version()
{
	JAR_LONG_VERSION=`java -classpath mim-$SIDE'stream.jar' se.mitm.version.Version 2>&1 | grep -m1 "Man in the Middle of Minecraft (MiM)" | sed 's/Man in the Middle of Minecraft (MiM): \(.*\)$/\1/' `
	JAR_VERSION=`echo $JAR_LONG_VERSION | sed -nE '/^v[0-9]+.[0-9]+-[0-9]+-.*$/p' | sed 's/^\(v[0-9]*\.[0-9]*-[0-9]*\)-.*$/\1/'`

	if [ -z $REQ_VERSION ]; then
		NET_LONG_VERSION=`curl -sfL $NET_DOWNLOAD/Version-mim-$SIDE'stream'.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/'`
		NET_VERSION=`echo $NET_LONG_VERSION | sed -nE '/^v[0-9]+.[0-9]+-[0-9]+-.*$/p' | sed 's/^\(v[0-9]*\.[0-9]*-[0-9]*\)-.*$/\1/'`
	else
		NET_VERSION=$REQ_VERSION
		echo ! Requested version manually set to [$NET_VERSION]
	fi

	[ -z "$NET_VERSION" ] && error_msg "Unable to determine the latest version of MiM"

	return 0; #TODO: required because something before sets the error
}

#--------------------------------------------------------------------------------------------------------------------------------

compile_jzmq_lib()
{
	[ -f /usr/local/lib/libjzmq.a ] && { echo "Compile Java binding for zmq :: SKIPPED"; return 0; }

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

	[ -d forge-1.12-14.21.1.2387-mdk ] && { rm -rf forge-1.12-14.21.1.2387-mdk || error_exit; }

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
		#[ -f forge-$FORGE_VERSION-mdk/$FORGE_SNAPSHOT/rename.jar ] && { echo "Preparing Minecraft sources :: SKIPPED"; return 0; }

		# v0.9-9
		[ -f forge-$FORGE_VERSION-mdk/$FORGE_SNAPSHOT/rename/patch/net/minecraft/util/Timer.class ] && { echo "Preparing Minecraft sources :: SKIPPED"; return 0; }
	fi

	# -----

	cd forge-$FORGE_VERSION-mdk || error_exit

	./gradlew -g gradle.cache :compileJava

	# merge assets (client.jar) and source (rename.jar)
	#
	cp $FORGE_SNAPSHOT/rename/output.jar $FORGE_SNAPSHOT/rename/output_.jar || error_exit	

	if (( $DEV )); then
		# jar tf mim-(up|down)stream.jar | grep "net/minecraft.*.class"
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/util/text/TextComponent.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/IPacket.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/NetworkManager\$1.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/NetworkManager\$2.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/NetworkManager\$QueuedPacket.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/NetworkManager.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/PacketBuffer.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/handshake/client/CHandshakePacket.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/play/server/SSpawnMobPacket.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/network/play/server/SSpawnPlayerPacket.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/util/text/StringTextComponent.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/util/text/TextFormatting.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/util/text/TranslationTextComponent.class
		zip -d $FORGE_SNAPSHOT/rename/output_.jar net/minecraft/util/Timer.class
	else
		PATCH_JAR=patch.jar
		echo == Downloading Minecraft patches ==
		curl -f -o $FORGE_SNAPSHOT/rename/$PATCH_JAR -L $NET_DOWNLOAD/$NET_VERSION/$PATCH_JAR || error_exit

		mkdir -p $FORGE_SNAPSHOT/rename/patch || error_ext
		pushd $FORGE_SNAPSHOT/rename/patch > /dev/null || error_exit
		jar xf ../patch.jar

		echo Patching sources ...
		jar uf ../output_.jar *
		popd > /dev/null
	fi

	#TODO: jar -C <dir> // Temporarily changes directories to dir while processing the following inputfiles argument.  Multiple -C dir inputfiles sets are allowed.

	mkdir -p $FORGE_SNAPSHOT/downloadClient/_client || error_exit
	pushd $FORGE_SNAPSHOT/downloadClient/_client > /dev/null || error_exit

	jar xf ../client.jar assets data log4j2.xml META-INF pack.mcmeta pack.png version.json 
	jar uf ../../rename/output_.jar *
	
	popd > /dev/null

	mv $FORGE_SNAPSHOT/rename/output_.jar $FORGE_SNAPSHOT/rename.jar || error_exit

	cd ..
}

#--------------------------------------------------------------------------------------------------------------------------------

download_mim() 
{
	if [ $SIDE == "up" ]; then
		PROPERTIES=mim-upstream.properties

		[ -f proxy.properties ] && { mv proxy.properties $PROPERTIES || error_exit; }
		[ -f mim-upstream.properties ] && { mv mim-upstream.properties mim-upstream.properties~; sed 's/^minecraft-server-names=/aliases=/' < mim-upstream.properties~ >mim-upstream.properties; }

		if (( $LOCAL )); then
			echo 'addr=0.0.0.0' > $PROPERTIES
			echo 'port=4499' >> $PROPERTIES
			echo 'aliases=127.0.0.1' >> $PROPERTIES
		fi
	fi

	# -----

	if (( ! $CLEAN )) && [ -z $REQ_VERSION ]; then
		if [ -f ./mim-$SIDE'stream.jar' ]; then
			JAR=( `echo $JAR_VERSION | sed 's/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)$/\1 \2 \3/'` )
			NET=( `echo $NET_VERSION | sed 's/^v\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)$/\1 \2 \3/'` )
			UPGRADE=0; for NR in 0 1 2; do [ ${JAR[$NR]} -lt ${NET[$NR]} ] && UPGRADE=1; done

			(( ! $UPGRADE )) && { echo "Download MiM-"$SIDE"stream component :: SKIPPED"; return 0; }

			echo "MiM-"$SIDE"stream-v"${JAR[0]}.${JAR[1]}-${JAR[2]}" installed, latest [v"${NET[0]}.${NET[1]}-${NET[2]}"], upgrading ..."
		fi
	fi

	# -----

	echo "== Downloading MiM ["$SIDE"stream] component =="
	curl -f -o ./mim-$SIDE'stream.jar.tmp' -L $NET_DOWNLOAD/$NET_VERSION/mim-$SIDE'stream.jar' || return 1
	[ -f ./mim-$SIDE'stream.jar' ] && { mv ./mim-$SIDE'stream.jar' ./mim-$SIDE'stream.jar~' || return 1; }
	mv ./mim-$SIDE'stream.jar.tmp' ./mim-$SIDE'stream.jar' || return 1
	echo $SIDE"stream: "`java -classpath mim-$SIDE'stream.jar' se.mitm.version.Version`
}

#--------------------------------------------------------------------------------------------------------------------------------

generate_run_script() 
{
	if [ $SIDE == "up" ]; then
		[ -f upstream.sh ] && { mv upstream.sh mim-upstream.sh~ || error_exit; }
	else
		[ -f downstream.sh ] && { mv downstream.sh mim.sh~ || error_exit; }
	fi

	# -----

	#if (( ! $CLEAN )); then
	#fi

	# -----

	PREFIX=''
	(( $LOCAL )) && PREFIX='local-'
	echo "== Generating ["$PREFIX$SIDE"stream] run script =="
		
	if [ $SIDE == "up" ]; then
		OUT=mim-upstream.sh
		(( $LOCAL )) && OUT=mim-upstream-local.sh
	else
		OUT=mim-downstream.sh
	fi

	# -----

	[ -f $OUT ] && { mv $OUT $OUT'~' || return 1; }
	# https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n
	echo '#!/bin/bash' > $OUT
	echo 'ARGS=$@'$'\n' >> $OUT

	#
	# basically don't have to have to escape anything except for single quotes, which can not occur inside single quotes
	# https://unix.stackexchange.com/questions/187651/how-to-echo-single-quote-when-using-single-quote-to-wrap-special-characters-in
	# http://tldp.org/LDP/Bash-Beginners-Guide/html/sect_07_01.html
	#

	# [ -f mim-downstream.jar ] || { echo "File [mim-downstream.jar] not found."; echo "Abort."; exit 1; }
	# grep -qa docker /proc/1/cgroup 2>/dev/null || { echo "Use [docker-compose] instead."; echo "Abort."; exit 1; }

	# https://stackoverflow.com/questions/20010199/how-to-determine-if-a-process-runs-inside-lxc-docker
	echo '[ -f mim-'$SIDE'stream.jar ] || { echo "File [mim-'$SIDE'stream.jar] not found."; echo "Abort."; exit 1; }' >> $OUT
	echo '[ -f docker-compose.yml ] && ! grep -qa docker /proc/1/cgroup 2>/dev/null && { echo "Use [\"docker-compose up\"] instead."; echo "Abort."; exit 1; }'$'\n' >> $OUT

	# while [ ! -z "$1" ]; do 
	#	[ "$1" == "--version" ] && { echo `java -classpath mim-downstream.jar se.mitm.version.Version`; exit 0; }; 
	#	[ "$1" == "--upgrade" ] && { curl -f --silent -o install.sh -L https://raw.githubusercontent.com/knev/mim-installer/master/install.sh; /bin/bash install.sh -d .; rm install.sh; exit 0; }; 
	#	shift; 
	# done
	#
	if [ $SIDE == "up" ]; then
		SWITCH="--upstream"
		(( $LOCAL )) && SWITCH="--local-upstream"
	fi
	echo 'while [ ! -z "$1" ]; do [ "$1" == "--version" ] && { echo `java -classpath mim-'$SIDE'stream.jar se.mitm.version.Version`; exit 0; }; [ "$1" == "--upgrade" ] && { curl -f --silent -o install.sh -L https://raw.githubusercontent.com/knev/mim-installer/master/install.sh; /bin/bash install.sh -d . '$SWITCH'; rm install.sh; exit 0; }; shift; done'$'\n' >> $OUT
	
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

	# v1.14.4 runtime libs
	#./ca/weblite/java-objc-bridge/1.0.0/java-objc-bridge-1.0.0-natives-osx.jar
	#./ca/weblite/java-objc-bridge/1.0.0/java-objc-bridge-1.0.0.jar
	#./com/google/code/gson/gson/2.8.0/gson-2.8.0.jar
	#./com/google/guava/guava/21.0/guava-21.0.jar
	#./com/ibm/icu/icu4j-core-mojang/51.2/icu4j-core-mojang-51.2.jar
	#./com/mojang/authlib/1.5.25/authlib-1.5.25.jar
	#./com/mojang/brigadier/1.0.17/brigadier-1.0.17.jar
	#./com/mojang/datafixerupper/2.0.24/datafixerupper-2.0.24.jar
	#./com/mojang/javabridge/1.0.22/javabridge-1.0.22.jar
	#./com/mojang/patchy/1.1/patchy-1.1.jar
	#./com/mojang/text2speech/1.11.3/text2speech-1.11.3.jar
	#./commons-codec/commons-codec/1.10/commons-codec-1.10.jar
	#./commons-io/commons-io/2.5/commons-io-2.5.jar
	#./commons-logging/commons-logging/1.1.3/commons-logging-1.1.3.jar
	#./io/netty/netty-all/4.1.25.Final/netty-all-4.1.25.Final.jar
	#./it/unimi/dsi/fastutil/8.2.1/fastutil-8.2.1.jar
	#./net/java/dev/jna/jna/4.4.0/jna-4.4.0.jar
	#./net/java/dev/jna/platform/3.4.0/platform-3.4.0.jar
	#./net/java/jinput/jinput/2.0.5/jinput-2.0.5.jar
	#./net/java/jutils/jutils/1.0.0/jutils-1.0.0.jar
	#./net/sf/jopt-simple/jopt-simple/5.0.3/jopt-simple-5.0.3.jar
	#./org/apache/commons/commons-compress/1.8.1/commons-compress-1.8.1.jar
	#./org/apache/commons/commons-lang3/3.5/commons-lang3-3.5.jar
	#./org/apache/httpcomponents/httpclient/4.3.3/httpclient-4.3.3.jar
	#./org/apache/httpcomponents/httpcore/4.3.2/httpcore-4.3.2.jar
	#./org/apache/logging/log4j/log4j-api/2.8.1/log4j-api-2.8.1.jar
	#./org/apache/logging/log4j/log4j-core/2.8.1/log4j-core-2.8.1.jar
	#./org/lwjgl/lwjgl-glfw/3.2.1/lwjgl-glfw-3.2.1-natives-macos.jar
	#./org/lwjgl/lwjgl-glfw/3.2.1/lwjgl-glfw-3.2.1.jar
	#./org/lwjgl/lwjgl-jemalloc/3.2.1/lwjgl-jemalloc-3.2.1-natives-macos.jar
	#./org/lwjgl/lwjgl-jemalloc/3.2.1/lwjgl-jemalloc-3.2.1.jar
	#./org/lwjgl/lwjgl-openal/3.2.1/lwjgl-openal-3.2.1-natives-macos.jar
	#./org/lwjgl/lwjgl-openal/3.2.1/lwjgl-openal-3.2.1.jar
	#./org/lwjgl/lwjgl-opengl/3.2.1/lwjgl-opengl-3.2.1-natives-macos.jar
	#./org/lwjgl/lwjgl-opengl/3.2.1/lwjgl-opengl-3.2.1.jar
	#./org/lwjgl/lwjgl-stb/3.2.1/lwjgl-stb-3.2.1-natives-macos.jar
	#./org/lwjgl/lwjgl-stb/3.2.1/lwjgl-stb-3.2.1.jar
	#./org/lwjgl/lwjgl/3.2.1/lwjgl-3.2.1-natives-macos.jar
	#./org/lwjgl/lwjgl/3.2.1/lwjgl-3.2.1.jar
	#./oshi-project/oshi-core/1.1/oshi-core-1.1.jar
	
	declare -a REQUIRED_LIBS=(
		"1|ca.weblite\/java-objc-bridge\/.*\.jar"
		"1|com.google.code.findbugs\/jsr305\/.*\.jar"
		"1|com.google.code.gson\/gson\/2.8.0\/.*\.jar"
		"1|com.google.guava\/guava\/21.0\/.*\.jar"
		"1|com.ibm.icu\/icu4j-core-mojang\/.*\.jar"
		"1|com.mojang\/authlib\/.*\.jar"
		"1|com.mojang\/brigadier\/.*\.jar"
		"1|com.mojang\/datafixerupper\/.*\.jar"
		"1|com.mojang\/javabridge\/.*\.jar"
		"1|com.mojang\/patchy\/.*\.jar"
		"1|com.mojang\/text2speech\/.*\.jar"
		"1|commons-codec\/commons-codec\/1.10\/.*\.jar"
		"1|commons-io\/commons-io\/2.5\/.*\.jar"
		"1|commons-logging\/commons-logging\/.*\.jar"
		"1|io.netty\/netty-all\/.*\.jar"
		"1|it.unimi.dsi\/fastutil\/.*\.jar"
		"1|net.minecraftforge\/eventbus\/.*\.jar"
		#"1|org.gobbly-gook\/lib\/.*\.jar"
		"1|net.java.dev.jna\/jna\/.*\.jar"
		"1|net.java.dev.jna\/platform\/.*\.jar"
		"1|net.java.jinput\/jinput\/.*\.jar"
		"1|net.java.jutils\/jutils\/.*\.jar"
		"1|net.sf.jopt-simple\/jopt-simple\/.*\.jar"
		"1|org.apache.commons\/commons-compress\/.*\.jar"
		"1|org.apache.commons\/commons-lang3\/.*\.jar"
		"1|org.apache.httpcomponents\/httpclient\/.*\.jar"
		"1|org.apache.httpcomponents\/httpcore\/.*\.jar"
		"1|org.apache.logging.log4j\/log4j-api\/.*\.jar"
		"1|org.apache.logging.log4j\/log4j-core\/.*\.jar"
		#"1|org.lwjgl\/lwjgl-glfw\/.*(?<!$ARCH)\.jar"
		#"1|org.lwjgl\/lwjgl-glfw\/.*$ARCH\.jar"
		"2|org.lwjgl\/lwjgl-glfw\/.*\.jar"
		"2|org.lwjgl\/lwjgl-jemalloc\/.*\.jar"
		"2|org.lwjgl\/lwjgl-openal\/.*\.jar"
		"2|org.lwjgl\/lwjgl-opengl\/.*\.jar"
		"2|org.lwjgl\/lwjgl-stb\/.*\.jar"
		"2|org.lwjgl\/lwjgl\/.*\.jar"
		"1|oshi-project\/oshi-core\/.*\.jar"
	)

	declare -a FOUND_LIBS=(`find forge-$FORGE_VERSION-mdk/gradle.cache/caches/modules-2/files-2.1 -type f -name "*.jar" `)

	declare -a CLASSPATH=()
	for REQ in ${REQUIRED_LIBS[@]}
	do 
		NR=${REQ%|*}
		PATTERN=${REQ/[0-9]|/}
		FOUND=( `echo ${FOUND_LIBS[@]} | tr ' ' ':' | perl -F":" -ane 'foreach (@F) { print "$_\n" if /^forge-'$FORGE_VERSION'-mdk\/gradle.cache\/caches\/modules-2\/files-2.1\/'$PATTERN'$/; }'` )

		# for JAR in ${FOUND[@]}; do echo $JAR; done
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

	LIB_PATH=\$MiM'/libs'
	[ -f /usr/local/lib/libjzmq.a ] && LIB_PATH='/usr/local/lib'

	echo -n 'java -Xms1G -Xmx1G' '-Djava.library.path="'$LIB_PATH'"' '-classpath "'$CLASSPATH':$MiM/forge-'$FORGE_VERSION'-mdk/'$FORGE_SNAPSHOT'/rename.jar:$MiM/mim-'$SIDE'stream.jar" ' >> ./$OUT
	if [[ $SIDE = "down" ]]; then
		echo -n 'se.mitm.server.DedicatedServerProxy ' >> ./$OUT
	else
		echo -n 'se.mitm.client.MinecraftClientProxy ' >> ./$OUT
		(( $LOCAL )) && echo -n '--local-upstream=true ' >> ./$OUT
	fi
	# https://unix.stackexchange.com/questions/108635/why-i-cant-escape-spaces-on-a-bash-script/108663#108663
	echo ' $ARGS' >> ./$OUT

	chmod +x ./$OUT
	echo '"java -classpath mim-'$SIDE'stream.jar" >> ./'$OUT

	# -----

	if [ $SIDE == "down" ]; then
		OUT=mim.sh
		echo '#!/bin/bash'$'\n' > $OUT

		echo 'while [ ! -z "$1" ]; do [ "$1" == "--upgrade" ] && { curl -f --silent -o install.sh -L https://raw.githubusercontent.com/knev/mim-installer/master/install.sh; /bin/bash install.sh -d .; rm install.sh; exit 0; }; shift; done'$'\n' >> $OUT
		
		echo 'trap "exit" INT TERM ERR' >> $OUT
		echo 'trap "kill 0" EXIT'$'\n' >> $OUT

		echo './mim-downstream.sh &' >> $OUT
		echo './mim-upstream-local.sh &'$'\n' >> $OUT

		echo 'wait' >> $OUT

		chmod +x ./$OUT
		echo '"trap; ./mim-(up|down)stream.sh &; wait" >> ./'$OUT
	fi
}

#--------------------------------------------------------------------------------------------------------------------------------

check_pre_reqs || error_exit

create_working_directory || error_exit
cd "$MIM_DIR"/ || error_exit

if (( $DOCKER )); then
	docker_build_image || error_exit
	docker_cp || error_exit
	generate_docker_compose || error_exit
	exit 0
fi

(( !$DEV )) && { check_latest_mim_version || error_exit; }
compile_jzmq_lib || error_exit
download_forge || error_exit
prep_forge || error_exit
(( $DEV )) && exit 0
download_mim || error_exit 
generate_run_script || error_exit

if [[ $SIDE = "down" ]]; then
	LOCAL=1
	UPSTREAM=1
	SIDE="up"

	download_mim || error_exit 
	generate_run_script || error_exit
fi

cd ..

#--------------------------------------------------------------------------------------------------------------------------------

echo "SUCCESS!"; exit 0
