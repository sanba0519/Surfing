#!/bin/sh

SKIPUNZIP=1
ASH_STANDALONE=1

CURRENT_MODULES_DIR="/data/adb/modules"
UPDATE_MODULES_DIR="/data/adb/modules_update"

magisk -v | grep -q lite && CURRENT_MODULES_DIR="/data/adb/lite_modules" && UPDATE_MODULES_DIR="/data/adb/lite_modules_update"

SURFING_PATH="$CURRENT_MODULES_DIR/Surfing"
BOX_BLL_PATH="/data/adb/box_bll"
BIN_PATH="$BOX_BLL_PATH/bin"

SCRIPTS_PATH="$BOX_BLL_PATH/scripts"
NET_PATH="/data/misc/net"
CTR_PATH="/data/misc/net/rt_tables"
CONFIG_FILE="$BOX_BLL_PATH/clash/config.yaml"
BACKUP_FILE="$BOX_BLL_PATH/clash/proxies/subscribe_urls_backup.txt"
ROUTING_BACKUP_FILE="$BOX_BLL_PATH/clash/etc/routing_config_backup.yaml"
INSTALL_DIR="/data/app"
HOSTS_FILE="$BOX_BLL_PATH/clash/etc/hosts"
HOSTS_PATH="$BOX_BLL_PATH/clash/etc"
HOSTS_BACKUP="$BOX_BLL_PATH/clash/etc/hosts.bak"

SURFING_TILE_ZIP="$MODPATH/SurfingTile.zip"
CURRENT_SURFING_TILE_DIR="$CURRENT_MODULES_DIR/SurfingTile"
UPDATE_SURFING_TILE_DIR="$UPDATE_MODULES_DIR/SurfingTile"

MODULE_PROP_PATH="$CURRENT_MODULES_DIR/Surfing/module.prop"
MODULE_VERSION_CODE=0
[ -f "$MODULE_PROP_PATH" ] && MODULE_VERSION_CODE=$(awk -F'=' '/versionCode/ {print $2}' "$MODULE_PROP_PATH")

if [ "$MODULE_VERSION_CODE" -lt 1647 ]; then
  INSTALL_TILE=true
else
  INSTALL_TILE=false
fi

init_busybox_toolchain() {
  chmod 755 "$BIN_PATH/busybox"
  cd "$BIN_PATH" && find . -type l -delete && ./busybox --install -s . && cd "$MODPATH"
}

extract_subscribe_urls() {
  if [ -f "$CONFIG_FILE" ]; then
    sed -n '/# 订阅地址相关/,/profile:.*↑/p' "$CONFIG_FILE" > "$BACKUP_FILE"
    
    if [ -s "$BACKUP_FILE" ]; then
      ui_print "Backed up subscription configuration."
    else
      ui_print "No subscription block found. Using default."
    fi
  else
    ui_print "Config file missing. Cannot extract subscriptions."
  fi
}

restore_subscribe_urls() {
  if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    awk -v backup="$BACKUP_FILE" '
      BEGIN { skip = 0 }
      /# 订阅地址相关/ {
        skip = 1
        while ((getline < backup) > 0) { print }
        close(backup)
        next
      }
      /profile:.*↑/ {
        skip = 0
        next
      }
      !skip { print }
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    ui_print "Restored subscription configuration."
  else
    ui_print "No valid backup found. Skipped restore."
  fi
}

extract_routing_config() {
  [ -f "$CONFIG_FILE" ] || return

  sed -n '/# ==== 用户分流配置开始/,/# ==== 用户分流配置结束/p' "$CONFIG_FILE" > "$ROUTING_BACKUP_FILE"
  if grep -q '# ==== 用户分流配置开始' "$ROUTING_BACKUP_FILE" && grep -q '# ==== 用户分流配置结束' "$ROUTING_BACKUP_FILE"; then
    ui_print "Backed up custom routing configuration."
  else
    : > "$ROUTING_BACKUP_FILE"
    ui_print "No custom routing block found. Using the new default."
  fi
}

restore_routing_config() {
  [ -s "$ROUTING_BACKUP_FILE" ] || return

  awk -v backup="$ROUTING_BACKUP_FILE" '
    BEGIN { skip = 0 }
    /# ==== 用户分流配置开始/ {
      skip = 1
      while ((getline < backup) > 0) { print }
      close(backup)
      next
    }
    /# ==== 用户分流配置结束/ {
      skip = 0
      next
    }
    !skip { print }
  ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  ui_print "Restored custom routing configuration."
}

install_custom_rule_files() {
  for rule_file in 自定义直连.list 自定义代理.list 自定义拒绝.list; do
    source_file="$MODPATH/box_bll/clash/etc/$rule_file"
    target_file="$HOSTS_PATH/$rule_file"
    [ -f "$target_file" ] && continue

    cp -f "$source_file" "$target_file"
  done
}

remove_legacy_rule_files() {
  legacy_rules_dir="$BOX_BLL_PATH/clash/rules"
  rm -f "$HOSTS_PATH/自定义规则.list"
  [ -d "$legacy_rules_dir" ] || return

  find "$legacy_rules_dir" -maxdepth 1 -type f \( -name '*.mrs' -o -name 'WebRTC.list' \) -exec rm -f {} \;
  ui_print "Removed legacy rule assets."
}

install_surfingtile_apk() {
  APK_SRC="$UPDATE_SURFING_TILE_DIR/system/app/com.surfing.tile/com.surfing.tile.apk"
  APK_TMP="$INSTALL_DIR/com.surfing.tile.apk"
  if [ -f "$APK_SRC" ]; then
    cp "$APK_SRC" "$APK_TMP"
    ui_print "Installing Surfingtile APK..."
    pm install "$APK_TMP"
    rm -f "$APK_TMP"
  else
    ui_print "Surfingtile APK not found"
  fi
}

install_surfingtile_module() {
  mkdir -p "$UPDATE_SURFING_TILE_DIR"
  mkdir -p "$CURRENT_SURFING_TILE_DIR"
  unzip -o "$SURFING_TILE_ZIP" -d "$UPDATE_SURFING_TILE_DIR" >/dev/null 2>&1
  cp -f "$UPDATE_SURFING_TILE_DIR/module.prop" "$CURRENT_SURFING_TILE_DIR"
  touch "$CURRENT_SURFING_TILE_DIR/update"
}

sync_version_from_module_prop() {
  dst_prop="$CURRENT_MODULES_DIR/Surfing/module.prop"
  if [ -f "$MODPATH/module.prop" ] && [ -d "$CURRENT_MODULES_DIR/Surfing" ]; then
    cp -f "$MODPATH/module.prop" "$dst_prop"
  fi
}

update_surfingtile_version_cache() {
  CORE_VER=$(grep "^version=" "$MODPATH/module.prop" | sed -n 's/.*-\([0-9a-z]\{7\}\).*/\1/p')
  [ -z "$CORE_VER" ] && return

  PREFS_PATHS="/data/data/com.surfing.tile/shared_prefs/OverviewsPrefs.xml /data/user/0/com.surfing.tile/shared_prefs/OverviewsPrefs.xml"

  for PREFS_FILE in $PREFS_PATHS; do
    if [ -f "$PREFS_FILE" ]; then
      sed -i "s/\(<string name=\"cached_core_version\">\)[^<]*\(<\/string>\)/\1$CORE_VER\2/g" "$PREFS_FILE"
    fi
  done
}

choose_volume_key() {
  timeout_seconds=10
  ui_print "Waiting for input (${timeout_seconds}s)..."
  line=$(timeout $timeout_seconds getevent -ql | awk '/KEY_VOLUME/ {print; exit}')
  if [ -z "$line" ]; then
      ui_print "No input detected. Running default option..."
      return 1
  fi
  if echo "$line" | grep -q "KEY_VOLUMEUP"; then
      return 0
  else
      return 1
  fi
}

choose_to_umount_hosts_file() {
  ui_print "Mount the hosts file to the system ?"
  ui_print "Volume Up: Mount"
  ui_print "Volume Down: Uninstall (default)"
  if choose_volume_key; then
    ui_print "Hosts file mounted"
  else
    ui_print "Uninstalling hosts file is complete"
    rm -f "$HOSTS_FILE"
  fi
}

remove_old_surfingtile(){
  rm -rf /data/adb/modules/Surfingtile 2>/dev/null
  rm -rf /data/adb/modules_update/Surfingtile 2>/dev/null
  rm -rf /data/adb/lite_modules/Surfingtile 2>/dev/null
  rm -rf /data/adb/lite_modules_update/Surfingtile 2>/dev/null
  rm -rf /data/adb/modules/Surfing_Tile 2>/dev/null
  rm -rf /data/adb/modules_update/Surfing_Tile 2>/dev/null
  rm -rf /data/adb/lite_modules/Surfing_Tile 2>/dev/null
  rm -rf /data/adb/lite_modules_update/Surfing_Tile 2>/dev/null
  pm uninstall "com.yadli.surfingtile" > /dev/null 2>&1 || pm uninstall --user 0 "com.yadli.surfingtile" > /dev/null 2>&1
}

if [ "$BOOTMODE" != true ]; then
  abort "Error: Please install via Magisk Manager / KernelSU Manager / APatch"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "Error: Please update your KernelSU Manager version"
fi

if [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10683 ]; then
  service_dir="/data/adb/ksu/service.d"
else
  service_dir="/data/adb/service.d"
fi
[ ! -d "$service_dir" ] && mkdir -p "$service_dir"

unzip -qo "${ZIPFILE}" -x 'META-INF/*' -d "$MODPATH"

remove_old_surfingtile
sync_version_from_module_prop

if [ -d "$BOX_BLL_PATH" ]; then
  ui_print "Updating..."
  ui_print "↴"

  cp -f "$MODPATH/box_bll/bin/busybox" "$BIN_PATH/busybox" && init_busybox_toolchain

  [ "$INSTALL_TILE" = "true" ] && install_surfingtile_module && install_surfingtile_apk
  mkdir -p "$BOX_BLL_PATH/clash/proxies" "$HOSTS_PATH"
  extract_subscribe_urls
  extract_routing_config

  [ -f "$HOSTS_FILE" ] && cp -f "$HOSTS_FILE" "$HOSTS_BACKUP"
  touch "$HOSTS_FILE"

  cp "$BOX_BLL_PATH/clash/config.yaml" "$BOX_BLL_PATH/clash/config.yaml.bak"
  cp "$BOX_BLL_PATH/scripts/box.config" "$BOX_BLL_PATH/scripts/box.config.bak"
  cp -f "$MODPATH/box_bll/clash/config.yaml" "$BOX_BLL_PATH/clash/"
  cp -f "$MODPATH/box_bll/clash/Toolbox.sh" "$BOX_BLL_PATH/clash/"
  cp -f "$MODPATH/box_bll/scripts/"* "$BOX_BLL_PATH/scripts/"
  install_custom_rule_files
  remove_legacy_rule_files

  OLD_CONFIG="$BOX_BLL_PATH/scripts/box.config.bak"
  NEW_CONFIG="$BOX_BLL_PATH/scripts/box.config"
  if [ -f "$OLD_CONFIG" ]; then
    ui_print "Migrating network service control settings..."
    TMP_CONFIG="${NEW_CONFIG}.tmp"
    cp -f "$NEW_CONFIG" "$TMP_CONFIG"
    VARS="enable_network_service_control bypass_via_iptables enable_cellular_proxy enable_wifi_proxy enable_mac_filter use_wifi_list_mode blacklist_wifi_macs whitelist_wifi_macs ap_list gid_list user_packages_list proxy_mode proxy_method ipv6"
    for var in $VARS; do
      val=$(grep "^${var}=" "$OLD_CONFIG" | cut -d'=' -f2-)
      [ -n "$val" ] && sed "s@^${var}=.*@${var}=${val}@" "$TMP_CONFIG" > "${TMP_CONFIG}.bak" && mv -f "${TMP_CONFIG}.bak" "$TMP_CONFIG"
    done
    mv -f "$TMP_CONFIG" "$NEW_CONFIG"
    ui_print "Settings migrated successfully"
  fi

  restore_subscribe_urls
  restore_routing_config

  for pid in $(pidof inotifyd); do
    if [ -f "/proc/${pid}/cmdline" ] && grep -qE "box.inotify|net.inotify|ctr.inotify" "/proc/${pid}/cmdline"; then
      kill "$pid"
    fi
  done
  nohup inotifyd "${SCRIPTS_PATH}/box.inotify" "$HOSTS_PATH" > /dev/null 2>&1 &
  nohup inotifyd "${SCRIPTS_PATH}/box.inotify" "$SURFING_PATH" > /dev/null 2>&1 &
  nohup inotifyd "${SCRIPTS_PATH}/net.inotify" "$NET_PATH" > /dev/null 2>&1 &
  nohup inotifyd "${SCRIPTS_PATH}/ctr.inotify" "$CTR_PATH" > /dev/null 2>&1 &
  [ -d "$CURRENT_SURFING_TILE_DIR" ] && inotifyd "${SCRIPTS_PATH}/box.inotify" "/data/system" >/dev/null 2>&1 &

  sleep 1
  cp -f "$MODPATH/box_bll/clash/etc/hosts" "$BOX_BLL_PATH/clash/etc/"
  rm -f "$BOX_BLL_PATH/clash/Toolbox.sh"
  rm -rf "$BOX_BLL_PATH/clash/Model.bin" "$BOX_BLL_PATH/clash/smart_weight_data.csv" "$BOX_BLL_PATH/scripts/box.upgrade"
  rm -rf "$MODPATH/box_bll"

  choose_to_umount_hosts_file
  update_surfingtile_version_cache
  am broadcast -a com.surfing.tile.ACTION_SAVE_CONFIG -p com.surfing.tile >/dev/null 2>&1
  ui_print "Update completed."
else
  ui_print "Installing..."
  ui_print "↴"
  mv "$MODPATH/box_bll" /data/adb/

  init_busybox_toolchain

  install_surfingtile_module
  install_surfingtile_apk
  ui_print "Module installation completed."
  choose_to_umount_hosts_file
fi

mv -f "$MODPATH/Surfing_service.sh" "$service_dir/"
rm -f "$SURFING_TILE_ZIP"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$UPDATE_SURFING_TILE_DIR" 0 0 0755 0644
set_perm_recursive "$BOX_BLL_PATH" 0 3005 0755 0644

set_perm_recursive "$BOX_BLL_PATH/scripts" 0 3005 0755 0700
set_perm_recursive "$BIN_PATH" 0 0 0755 0755
set_perm_recursive "$BOX_BLL_PATH/clash/etc" 0 0 0755 0644

set_perm "$service_dir/Surfing_service.sh" 0 0 0700
chmod ugo+x "$BOX_BLL_PATH/scripts/"*

rm -f customize.sh
