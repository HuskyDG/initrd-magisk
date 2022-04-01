# initrd-magisk
Another simple way to integrate Magisk into Android-x86 project (BlissOS, PrimeOS, ...)


## How to use?

1. In Android-x86 directory (which contain initrd.img, system.img, data, or data.img, ...), rename `initrd.img` to `initrd_real.img` and put `initrd-magisk` as `initrd.img`.
2. Download **magisk apk** and put it as `magisk.apk` in Android-88 directory.

## Build initrd on Linux environment

1. Clone this repo by:

```
git clone http://github.com/huskydg/initrd-magisk
```

2. Change current directory to `~/initrd-magisk`:
```
cd ~/initrd-magisk
```

3. Build with these command:
```
chmod -R 777 *; find * | cpio -o -H newc | gzip > ../initrd-magisk.img
```
