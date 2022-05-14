# initrd-magisk
Another easy and convenient way to integrate Magisk into Android-x86 project (BlissOS, PrimeOS, ...). Check out [Wiki page](http://github.com/huskydg/initrd-magisk/wiki) for install instructions and more information.


## Build your own initrd on Linux environment

> initrd-magisk that is built from GitHub actions is buggy


1. Prepare environment:
```
apt update; apt upgrade; pkg install git; pkg install cpio
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
