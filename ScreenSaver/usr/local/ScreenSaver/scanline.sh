#!/bin/sh

# called by /sbin/dd -> /usr/local/ScreenSaver/dd.sh

PATH="/usr/local/ScreenSaver:$PATH"
CONFIGFILE="/mnt/onboard/.addons/screensaver/screensaver.cfg"

#
# configuration
#
config() {
    local value
    value=$(grep -m 1 "^$1=" "$CONFIGFILE")
    value="${value:$((1+${#1}))}"
    [ "$value" != "" ] && echo "$value" || echo "$2"
}

#
# avoid calling the hook
#
dd() {
    /bin/dd "$@" 2> /dev/null
}

#
# force screen refresh
#
refresh() {
    # I'm too lazy, draw black/white for now.
    pngshow /usr/local/ScreenSaver/1px-black.png
    pngshow /usr/local/ScreenSaver/1px-white.png
}

#
# set framebuffer geometry variables
#
geometry() {
    set -- $(fbset | grep geometry)
    width=$2
    widthbs=$(($2*2))
    height=$3
    line=$4
    linebs=$(($4*2))
}

#
# visualize the scanline
#
draw() {
    offset=$((height-$1))

    dd bs="$linebs" seek=$(($offset-1)) count=1 if=/dev/urandom of=/dev/fb0
    dd bs="$linebs" seek=$(($offset+1)) count=1 if=/dev/urandom of=/dev/fb0

    refresh
}

#
# grab the pattern
#
pattern() {
    offset=$(($height-$1))

    set -- $(
    hexdump -v -e $line'/2 "%04x " "\n"' -s $(($linebs*$offset)) -n $widthbs /dev/fb0 \
    | md5sum
    )

    echo "$1"

    # visual pattern:
    #    | sed -r -e 's/  */ /g' -e 's/[0-7][0-9a-f]{3} /b/g' -e 's/[0-9a-f]{4} /w/g' \
    #             -e 's/w{5}w*/W/g' -e 's/b{5}b*/B/g'
}

offset=$(config offset 1)
debug=$(config debug 0)
standby=$(config standby)
poweroff=$(config poweroff)

cd /mnt/onboard/.addons/screensaver || exit
rnd="$RANDOM$RANDOM$RANDOM"
set -- *.png
file="$(eval 'echo "${'$((1 + $rnd % $#))'}"')"
set -- off/*.png
powerfile="$(eval 'echo "${'$((1 + $rnd % $#))'}"')"

# optimistic caching
cat "$powerfile" "$file" > /dev/null &

if [ ! -e "$powerfile" ]
then
    powerfile="$file"
fi

if [ "$debug" == "1" ]
then
    geometry
    echo -------- >> /mnt/onboard/.addons/screensaver/scanline.txt
    oldpattern=""
    for i in $(seq 1 1000)
    do
       curpattern=$(pattern $offset) 

       if [ "$curpattern" != "$oldpattern" ]
       then
           echo [ $(date) ] $curpattern >> /mnt/onboard/.addons/screensaver/scanline.txt
           oldpattern="$curpattern"
           draw $offset &
       fi
       sleep 0.05
    done

    exit
fi

for delay in $(config delay 0)
do
    sleep $delay
    geometry
    pattern=$(pattern $offset)

    if [ "$pattern" = "$standby" ]
    then
        wait # for pngshow
        pngshow "$file" &
    elif [ "$pattern" = "$poweroff" ]
    then
        wait # for pngshow
        pngshow "$powerfile" &
    fi
done
