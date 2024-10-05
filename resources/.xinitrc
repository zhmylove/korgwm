## Basic xdg variables
export XDG_RUNTIME_DIR=/run/user/1000/
export XDG_CURRENT_DESKTOP=generic

## This makes gtk portal usable with korgwm
systemctl --user import-environment DISPLAY XAUTHORITY
systemctl --user restart xdg-desktop-portal-gtk

## Some startup commands
flameshot &
xrdb -merge $HOME/.Xresources
xset dpms 0 0 0
xset s off
xsetroot -cursor_name left_ptr
export NO_AT_BRIDGE=1
setxkbmap -layout us,ru -option grp:alt_shift_toggle,compose:ralt

## Set background image
feh --bg-center $HOME/src/korgwm/resources/background_fhd.png

## Execute korgwm(1)
exec korgwm
