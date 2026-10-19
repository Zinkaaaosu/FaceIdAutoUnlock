TARGET := iphone:clang:latest:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FaceAutoUnlock

FaceAutoUnlock_FILES = Tweak.x
FaceAutoUnlock_CFLAGS = -fobjc-arc
FaceAutoUnlock_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
