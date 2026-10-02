LOCAL_PATH := device/xiaomi/lmi
PRODUCT_RELEASE_NAME := lmi
PRODUCT_SHIPPING_API_LEVEL := 29
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_VIRTUAL_AB_OTA := false
PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH)

$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

PRODUCT_PACKAGES += \
    qcom_decrypt \
    qcom_decrypt_fbe \
    android.hardware.fastboot@1.0-impl-mock \
    fastbootd
