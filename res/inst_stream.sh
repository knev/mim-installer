#!/bin/bash

SIDE="up"
NET_DOWNLOAD=https://www.mitm.se/mim-install

echo '#!/bin/bash'$'\n' > $SIDE'stream.sh'

echo '[ -f mitm-'$SIDE'stream.jar ] || { echo "File [mitm-'$SIDE'stream.jar] not found. Abort."; exit 1; }'$'\n' >> $SIDE'stream.sh'

# basically don't have to have to escape anything except for single quotes, which aren't escaped inside single quotes
# https://unix.stackexchange.com/questions/187651/how-to-echo-single-quote-when-using-single-quote-to-wrap-special-characters-in
# https://stackoverflow.com/questions/2188199/how-to-use-double-or-single-brackets-parentheses-curly-braces
#
#[ -f mitm-downstream.jar ] || { echo "File [mitm-downstream.jar] not found. Abort."; exit 1; }
#INST_VERSION=`java -classpath mitm-downstream.jar se.mitm.version.Version 2>&1 | grep -m1 MiTM-of-minecraft | sed 's/MiTM-of-minecraft: \(.*\)$/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
#NET_VERSION=`curl -sfL https://mitm.se/mim-install/mitm-stream/Version.java | grep -m1 commit | sed 's/.*commit=[ ]*\"\([^"]*\)\";/\1/' | sed 's/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'`
#[ -n "$NET_VERSION" ] && [ "$INST_VERSION" != "$NET_VERSION" ] && { echo "upstream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }
#
echo 'INST_VERSION=`java -classpath mitm-'$SIDE'stream.jar se.mitm.version.Version 2>&1 | grep -m1 MiTM-of-minecraft | sed '\''s/MiTM-of-minecraft: \(.*\)$/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
echo 'NET_VERSION=`curl -sfL '$NET_DOWNLOAD'/mitm-'$SIDE'stream/Version.java | grep -m1 commit | sed '\''s/.*commit=[ ]*\"\([^"]*\)\";/\1/'\'' | sed '\''s/^\(v[0-9]*.[0-9]*-[0-9]*\)-.*$/\1/'\''`' >> $SIDE'stream.sh'
echo '[ -n "$NET_VERSION" ] && [ "$INST_VERSION" != "$NET_VERSION" ] && { echo "upstream-"$INST_VERSION" installed, latest ["$NET_VERSION"], please upgrade ..."; read -s -n 1 -p "Press [KEY] to continue ..."; echo; }'$'\n' >> $SIDE'stream.sh'

chmod +x ./$SIDE'stream.sh'

exit 0


MiTM=/Users/dev/Metaverse/MiM
[ -d $MiTM ] || echo "Error: Invalid target directory "$MiTM
MCP=$MiTM/mcp940
MCPLIBS=$MCP/jars/libraries

#java -Xms1G -Xmx1G -Djava.library.path="$MiTM/libs" -classpath "$MCPLIBS/ca/weblite/java-objc-bridge/1.0.0/java-objc-bridge-1.0.0-natives-osx.jar:$MCPLIBS/ca/weblite/java-objc-bridge/1.0.0/java-objc-bridge-1.0.0.jar:$MCPLIBS/com/google/code/findbugs/jsr305/3.0.1/jsr305-3.0.1-sources.jar:$MCPLIBS/com/google/code/findbugs/jsr305/3.0.1/jsr305-3.0.1.jar:$MCPLIBS/com/google/code/gson/gson/2.8.0/gson-2.8.0.jar:$MCPLIBS/com/google/guava/guava/21.0/guava-21.0.jar:$MCPLIBS/com/ibm/icu/icu4j-core-mojang/51.2/icu4j-core-mojang-51.2.jar:$MCPLIBS/com/mojang/authlib/1.5.25/authlib-1.5.25.jar:$MCPLIBS/com/mojang/patchy/1.1/patchy-1.1.jar:$MCPLIBS/com/mojang/realms/1.10.17/realms-1.10.17.jar:$MCPLIBS/com/mojang/text2speech/1.10.3/text2speech-1.10.3.jar:$MCPLIBS/com/paulscode/codecjorbis/20101023/codecjorbis-20101023.jar:$MCPLIBS/com/paulscode/codecwav/20101023/codecwav-20101023.jar:$MCPLIBS/com/paulscode/libraryjavasound/20101123/libraryjavasound-20101123.jar:$MCPLIBS/com/paulscode/librarylwjglopenal/20100824/librarylwjglopenal-20100824.jar:$MCPLIBS/com/paulscode/soundsystem/20120107/soundsystem-20120107.jar:$MCPLIBS/commons-codec/commons-codec/1.10/commons-codec-1.10.jar:$MCPLIBS/commons-io/commons-io/2.5/commons-io-2.5.jar:$MCPLIBS/commons-logging/commons-logging/1.1.3/commons-logging-1.1.3.jar:$MCPLIBS/io/netty/netty-all/4.1.9.Final/netty-all-4.1.9.Final.jar:$MCPLIBS/it/unimi/dsi/fastutil/7.1.0/fastutil-7.1.0.jar:$MCPLIBS/net/java/dev/jna/jna/4.4.0/jna-4.4.0.jar:$MCPLIBS/net/java/dev/jna/platform/3.4.0/platform-3.4.0.jar:$MCPLIBS/net/java/jinput/jinput/2.0.5/jinput-2.0.5.jar:$MCPLIBS/net/java/jinput/jinput-platform/2.0.5/jinput-platform-2.0.5-natives-osx.jar:$MCPLIBS/net/java/jutils/jutils/1.0.0/jutils-1.0.0.jar:$MCPLIBS/net/sf/jopt-simple/jopt-simple/5.0.3/jopt-simple-5.0.3.jar:$MCPLIBS/org/apache/commons/commons-compress/1.8.1/commons-compress-1.8.1.jar:$MCPLIBS/org/apache/commons/commons-lang3/3.5/commons-lang3-3.5.jar:$MCPLIBS/org/apache/httpcomponents/httpclient/4.3.3/httpclient-4.3.3.jar:$MCPLIBS/org/apache/httpcomponents/httpcore/4.3.2/httpcore-4.3.2.jar:$MCPLIBS/org/apache/logging/log4j/log4j-api/2.8.1/log4j-api-2.8.1.jar:$MCPLIBS/org/apache/logging/log4j/log4j-core/2.8.1/log4j-core-2.8.1.jar:$MCPLIBS/org/lwjgl/lwjgl/lwjgl/2.9.2-nightly-20140822/lwjgl-2.9.2-nightly-20140822.jar:$MCPLIBS/org/lwjgl/lwjgl/lwjgl-platform/2.9.2-nightly-20140822/lwjgl-platform-2.9.2-nightly-20140822-natives-osx.jar:$MCPLIBS/org/lwjgl/lwjgl/lwjgl_util/2.9.2-nightly-20140822/lwjgl_util-2.9.2-nightly-20140822.jar:$MCPLIBS/oshi-project/oshi-core/1.1/oshi-core-1.1.jar:$MCP/bin/minecraft:$MCP/jars:$MiTM/mitm-upstream.jar" se.mitm.client.MinecraftClientProxy
