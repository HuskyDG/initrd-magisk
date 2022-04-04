# initrd-magisk
Another simple way to integrate Magisk into Android-x86 project (BlissOS, PrimeOS, ...)


## How to use?

Download initrd-magisk from [Release page](https://github.com/HuskyDG/initrd-magisk/releases)

1. In Android-x86 directory (which contain initrd.img, system.img, data, or data.img, ...), rename `initrd.img` to `initrd_real.img` and put `initrd-magisk` as `initrd.img`.
2. Download **magisk apk** and put it as `magisk.apk` in Android-x86 directory.

Android x86 directory will be like this:

- ...
- data.img or data folder
- findme
- initrd.img (initrd-magisk)
- initrd_real.img (original initrd.img)
- install.img
- kernel
- magisk.apk
- ramdisk.img (if Android 9 and bellow)
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
  - On rootfs, directly add magisk binaries into `/android/magisk` and magisk services into `init.rc`
  - On system-as-root, mount tmpfs on `/android/dev`, mount overlayfs on `/system/etc/init` and add magisk binaries and `magisk.rc`.
  - Patch sepolicy file, dump it into `/android/dev/.overlay/sepolicy` and mount bind into `/sepolicy` or vendor precompiled sepolicy.
  - Unmount `/android/dev`
- `init` switch root to `/android` and execute `/init` to boot into Android.

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

4. Default is x86_64 (64bit)
```
cat <<EOF >bin/info.sh
IS64BIT=true
ABI=x86_64
ABI32=x86
EOF
```

  If you want to build initrd-magisk for Android x86 (32bit):

```
cat <<EOF >bin/info.sh
IS64BIT=false
ABI=x86
ABI32=x86
EOF
```


5. Build with these command:
```
chmod -R 777 *; find * | cpio -o -H newc | gzip > ../initrd-magisk.img
```
</details>


## Important

- If you have `rusty-magisk` installed (BlissOS 14, PrimeOS 2.0 come with `rusty-magisk` installed), `initrd-magisk` will try to invalidate it. **It's RECOMMENDED to remove it**.
- If you update Android-x86 OTA, it might wipe out `initrd.img` so you will need to do again.

