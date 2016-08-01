#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

define Profile/Default
	NAME := Mikrotik Default Profile (all devices)
	PACKAGES :=
	PRIORITY := 1
endef

define Profile/Default/Description
	Default package set compatible with most Mikrotik boards.
endef
$(eval $(call Profile,Default))
