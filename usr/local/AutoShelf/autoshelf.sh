#!/bin/sh

PATH="/usr/local/AutoShelf":"$PATH"

udev_workarounds() {
    # udev kills slow scripts
    if [ "$SETSID" != "1" ]
    then
        SETSID=1 setsid "$0" "$@" &
        exit
    fi

    # udev calls twice. mkdir lock
    mkdir /tmp/autoshelf-lock || exit
    sleep 30 && rmdir /tmp/autoshelf-lock &
}

filesystem() {
    find /mnt/ -not -path '*/\.*' | sort
}

autoshelf() {
    echo "DELETE FROM Shelf WHERE InternalName LIKE '%/';"
    echo "DELETE FROM ShelfContent WHERE ShelfName LIKE '%/';"

    i=0

    sqlite3 /mnt/onboard/.kobo/KoboReader.sqlite "
    SELECT ContentID FROM content
    WHERE ContentID LIKE 'file:///mnt/%'
      AND ContentID NOT LIKE '%#%'
      AND ContentID NOT LIKE '%/.%'
      AND ContentType != 9
    ORDER BY ContentID
    ;" | while read file
    do
        i=$(($i+1))
        date="strftime('%Y-%m-%dT%H:%M:%SZ','now','-$i minute')"
        file=$(echo "$file" | sed -e "s@'@''@g")
        shelf=$(dirname "$file" | sed -r -e 's@^file://*mnt//*(onboard|sd)/*@@')
        word=$(basename "$file")
        for number in $word; do break; done
        if [ "$shelf" == "" ]
        then
            series="$word"
        else
            series="$shelf"
        fi

        if [ "$shelf" != "$prevshelf" ]
        then
            prevshelf="$shelf"
            echo "REPLACE INTO Shelf VALUES($date,'$shelf/','$shelf/',$date,'$shelf/',NULL,'false','true','false');"
        fi

        echo "INSERT INTO ShelfContent VALUES('$shelf/','$file',$date,'false','false');"

        echo "
        UPDATE content
        SET Series='$series', SeriesNumber='$number', DateCreated=$date, DateAdded=$date
        WHERE ContentID='$file'
        ;"
    done
}

udev_workarounds

for i in $(seq 1 10)
do
    sleep 2

    if [ -e /mnt/onboard/.kobo/KoboReader.sqlite ]
    then
        break
    fi
done

if [ -e /mnt/onboard/.kobo/KoboReader.sqlite ]
then
    result=$(autoshelf)

    if echo "$result" | md5sum -c /usr/local/AutoShelf/md5sum
    then
        echo "Already done..."
    else
        echo "Updating database..."
        echo "$result" | md5sum > /usr/local/AutoShelf/md5sum
        echo "$result" | sqlite3 /mnt/onboard/.kobo/KoboReader.sqlite
    fi
fi

wait