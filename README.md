# initrd-magisk
Another easy and convenient way to integrate Magisk, add support `boot.img` for Magisk into Android-x86 project (BlissOS, PrimeOS, ...). Check out [Wiki page](http://github.com/huskydg/initrd-magisk/wiki) for install instructions and more information.

<img src="https://i.imgur.com/1BbSrTp.jpg"/> 


## Build your own initrd on Linux environment

If you want to implement magisk support directly into `initrd.img` instead of using split two initrd image, you can build `initrd-magisk` with all files added from `initrd.img` into `initrd/first_stage`, `initrd-magisk` will  then stop finding original initrd.

Make `initrd-magisk.img` pre-rooted with Magisk by default (user can still have choice to uninstall magisk through Magisk app if they don't need): decompress `boot.img.gz` to `boot.img `, patch boot image through Magisk app. Compress patched boot image and put it as `initrd/boot.img.gz`.

1. Prepare environment:
- For Termux (Android):
```
apt update; apt upgrade; pkg install git; pkg install cpio
```
- For Ubuntu (Linux):
```
sudo apt update
sudo apt upgrade
sudo apt-get install git
sudo apt-get install cpio
```

2. Clone this repo by:

```
git clone http://github.com/huskydg/initrd-magisk
```

3. Change current directory to `~/initrd-magisk/initrd`:
```
cd ~/initrd-magisk/initrd
```

4. Build with these command:
```
chmod -R 777 *; ln -fs /bin/ld-linux.so.2 lib/ld-linux.so.2; find * | cpio -o -H newc | gzip > ../initrd-magisk.img
```

## Credits

- [Magisk](http://github.com/topjohnwu/magisk): The most famous root solution on Android
