#!/bin/bash

# Defaults
quality="720p50"
userAgent='Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:49.0) Gecko/20100101 Firefox/49.0'

# fr5-0, fr5-1, fr5-2, fr5-3, fr5-4, fr5-5
# fra3-0, fra3-1, fra3-2, fra3-3
# zh2-0, zh2-1, zh2-2, zh2-3, zh2-4, zh2-5, zh2-6, zh2-7, zh2-8, zh2-9, zba6-0, zba6-1, zba6-2
# 1und1-fra1902-1, 1und1-fra1902-2, 1und1-fra1902-3, 1und1-fra1902-4, 1und1-hhb1000-1, 1und1-hhb1000-2, 1und1-hhb1000-3, 1und1-hhb1000-4
# 1und1-dus1901-1, 1und1-dus1901-2, 1und1-dus1901-3, 1und1-dus1901-4,1und1-ess1901-1,1und1-ess1901-2,1und1-stu1903-1,1und1-stu1903-2
# matterlau1-0, matterlau1-1, matterzrh1-0, matterzrh1-1

videoServer="fr5-0"
platform="hls5"
ssl_mode=1
multi=0
dolby=0
audio2=0

##
##
##

while getopts "c:q:" opt; do
case $opt in
c)
channelID=$OPTARG
;;
q)
quality=$OPTARG
;;
*)
  #Printing error message
  echo "Usage: $0 -c <channelID> [-q <quality>]"
  exit 1
;;
esac
done

if [ -z $channelID ] ; then
  echo "Usage: $0 -c <channelID> -q [<quality>]"
  exit 1
fi

liveURL="https://streams.wilmaa.com/m3u8/get?channelId=$channelID"

originalPlaylist=$(curl -L -si $liveURL)

head=true
while read -r line; do
    if $head; then
        if [[ $line = $'\r' ]]; then
            head=false
        else
            header="$header"$'\n'"$line"
        fi
    else
        body="$body"$'\n'"$line"
    fi
done < <(echo "$originalPlaylist")

redirectURL=$(echo "$header" | grep Location | head -n 1 | cut '-d ' '-f2')

if [ -z $redirectURL ] ; then
        echo "Connection error, exiting..."
        exit 1
fi

baseURL=$(echo $redirectURL | sed -e "s/\/master.m3u8.*//")

videoToken=$(echo $originalPlaylist | sed 's/.*=\([[:alnum:]]*\).*/\1/')

case $quality in
  1080p50) #
        final_quality_video=7800
        final_bandwidth=8000000
        final_resolution=1920x1080
        final_framerate=50
    ;;
  1080p25) #
        final_quality_video=4799
        final_bandwidth=4999000
        final_resolution=1920x1080
        final_framerate=25
    ;;
  720p25) #
        final_quality_video=2800
        final_bandwidth=3000000
        final_resolution=1280x720
        final_framerate=25
    ;;
  576p50) #
        final_quality_video=2799
        final_bandwidth=2999000
        final_resolution=1024x576
        final_framerate=50
    ;;
  432p25) #
        final_quality_video=1300
        final_bandwidth=1500000
        final_resolution=768x432
        final_framerate=25
    ;;
  *) # 720p50
        final_quality_video=4800
        final_bandwidth=5000000
        final_resolution=1280x720
        final_framerate=50
    ;;
esac

final_quality_audio="t_track_audio_bw_128_num_0"
final_codec="avc1.4d4020,mp4a.40.2"

pattern="(.*)(NAME=\")(.*)(\",DEFAULT=.*)($final_quality_audio.*?z32=)(.*)\""
if [[ $originalPlaylist =~ $pattern ]] ; then
    language="${BASH_REMATCH[3]}"
else
    echo "Could not get info (0), exiting...."
    exit 1
fi

case $language in
  "Deutsch")
        language="deu"
    ;;
  "English")
        language="eng"
    ;;
  "Français")
        language="fra"
    ;;
  "Italiano")
        language="ita"
    ;;
  "Español")
        language="spa"
    ;;
  "Português")
        language="por"
    ;;
  *)
        language="ita"
    ;;
esac

pattern='(.*)(t_track_audio_bw_128_num_0)([^?]+)(.*)'
if [[ $originalPlaylist =~ $pattern ]] ; then
    videoStream="${BASH_REMATCH[3]}"
else
    echo "Could not get info (1), exiting...."
    exit 1
fi

link_video_url="$baseURL/t_track_video_bw_$[final_quality_video]_num_0.m3u8?z32=$videoToken"
link_audio_url="$baseURL/$final_quality_audio$videoStream?z32=$videoToken"

pattern="s/https:\/\/zattoo-hls[57]-live.akamaized.net/https:\/\/$videoServer-hls5-live.zahs.tv/g"
link_video_url=$(echo $link_video_url | sed -e "$pattern")

pattern="s/https:\/\/zattoo-hls[57]-live.akamaized.net/https:\/\/$videoServer-hls5-live.zahs.tv/g"
link_audio_url=$(echo $link_audio_url | sed -e "$pattern")

pattern="s/https:\/\/.*\.zahs.tv/https:\/\/$videoServer-hls5-live.zahs.tv/g"
link_video_url=$(echo $link_video_url | sed -e "$pattern")

pattern="s/https:\/\/.*.\zahs.tv/https:\/\/$videoServer-hls5-live.zahs.tv/g"
link_audio_url=$(echo $link_audio_url | sed -e "$pattern")

read -r -d '' m3u8Content << EOF
#EXTM3U
#EXT-X-VERSION:5
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-group",NAME="$language",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="$language",URI="$link_audio_url"
#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS="$final_codec",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO="audio-group",CLOSED-CAPTIONS=NONE
$link_video_url
EOF

echo "$m3u8Content" | /usr/bin/ffmpeg -hide_banner -nostats -loglevel panic -protocol_whitelist file,pipe,http,https,tcp,tls -i pipe: -vcodec copy -acodec copy -bsf:v h264_mp4toannexb,dump_extra -f mpegts -tune zerolatency pipe:1

