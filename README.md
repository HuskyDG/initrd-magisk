# initrd-magisk
Another easy and convenient way to integrate Magisk into Android-x86 project (BlissOS, PrimeOS, ...)


## How to use?

Download initrd-magisk from [Release page](https://github.com/HuskyDG/initrd-magisk/releases)

### First way

1. In Android-x86 directory, rename `initrd.img` to `initrd_real.img` and put `initrd-magisk` as `initrd.img`.
2. Download **magisk apk** and put it as `magisk.apk` in Android-x86 directory.

### Second way

1. Put `initrd-magisk.img` into Android-x86 directory. Search for line `initrd /$SOURCE_NAME/initrd.img` in GRUB custom code and change it to `initrd /$SOURCE_NAME/initrd-magisk.img`
2. Download **magisk apk** and put it as `magisk.apk` in Android-x86 directory.


Android x86 directory will be like this:

- ...
- data.img or data folder ← userdata will be store here
- findme
- initrd.img (initrd-magisk.img) ←initial ramdisk
- initrd_real.img (initrd.img) ← Original initrd image will be loaded by initrd-magisk
- install.img
- kernel
- magisk.apk ← This Magisk version will be loaded by initrd-magisk, if this file does not exist, it will boot Android without Magisk
- ramdisk.img ←exist if Android 9 and bellow (rootfs)
- system.img
- ...


## How does it works?

<details>
<summary>Show all</summary>

### initrd-magisk boot stage

- System launched with **initrd-magisk** (`initrd.img`) unpacked into root directory in first stage, then unpack original `initrd_real.img` to root directory.
- Extract `magisk.apk` and put binaries into `/magisk`
- Put `99_magisk` script into `/scripts`
- Launch `init` script from original `initrd_real.img` and continue to boot.

### original initrd boot stage

- Execute `99_magisk` script to patch Android's root directory
  - Mount tmpfs on `/android/dev`.
  - **On rootfs (read-write rootdir)**, directly add magisk binaries into `/android/magisk` and inject magisk services into `/init.rc`. **On system-as-root (read-only rootdir)**, mount overlay on `/android/system/etc/init`, add magisk binaries into `/android/system/etc/init/magisk` and inject magisk services into  `/android/system/etc/init/magisk.rc`.
  - **Pre-init sepolicy patch**: Patch sepolicy file by using `magiskpolicy` tool, dump it into `/android/dev/.overlay/sepolicy` and mount bind on `/sepolicy` or vendor precompiled sepolicy.
  - Unmount `/android/dev`.
- `init` switch root directory to `/android` and execute `/init` to boot Android.

### Android boot stage

- Android boot with Magisk

</details>


## Build your own initrd on Linux environment

<details>
<summary>Show all</summary>

1. Prepare environment:
```
apt update; apt upgrade
pkg install git
pkg install cpio
```

2. Clone this repo by:

```
git clone http://github.com/huskydg/initrd-magisk
```

3. Change current directory to `~/initrd-magisk`:
```
cd ~/initrd-magisk
```

4. Build with these command:
```
chmod -R 777 *; find * | cpio -o -H newc | gzip > ../initrd-magisk.img
```
</details>

## Other features

- Disable all magisk module with flag `FIXFS=1`


## Important

- If you have `rusty-magisk` installed (BlissOS 14, PrimeOS 2.0 come with `rusty-magisk` installed), `initrd-magisk` will try to invalidate it. **It's RECOMMENDED to remove it**.
- If you update Android-x86 OTA, it might wipe out `initrd.img` so you will need to do again.

