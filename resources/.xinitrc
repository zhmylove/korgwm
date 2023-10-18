xrdb -merge $HOME/.Xresources
xset dpms 0 0 0
xset s off
xsetroot -cursor_name left_ptr
setxkbmap -layout us,ru -option grp:alt_shift_toggle,compose:ralt
feh --bg-center $HOME/src/korgwm/resources/background_fhd.png
exec korgwm
