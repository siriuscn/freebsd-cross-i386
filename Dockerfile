# This Dockerfile creates a static build image for CI

FROM alpine:3.8
LABEL maintainer="Sirius <siriuscn@qq.com>" \
    references="Greg V <greg@unrelenting.technology>" \
    references="db@donbowman.ca"

# Install pkg on Linux to download dependencies into the FreeBSD root
RUN apk add --no-cache curl gcc pkgconf make autoconf automake libtool musl-dev \ 
        xz-dev bzip2-dev zlib-dev fts-dev libbsd-dev openssl-dev libarchive-dev libarchive-tools

RUN mkdir /pkg && \
	curl -Ls https://github.com/freebsd/pkg/archive/1.10.5.tar.gz | \
		bsdtar -xf - -C /pkg && \
	cd /pkg/pkg-* && \
	./autogen.sh && \
	CFLAGS="-D__BEGIN_DECLS='' -D__END_DECLS='' -DALLPERMS='S_ISUID|S_ISGID|S_ISVTX|S_IRWXU|S_IRWXG|S_IRWXO' -Droundup2='roundup' -Wno-cpp" \
		LDFLAGS="-lfts" ./configure && \
	touch /usr/include/sys/unistd.h && \
	touch /usr/include/sys/sysctl.h && \
	make -j4 install && \
	cd / && \
	rm -rf /pkg /usr/local/sbin/pkg2ng

# Download FreeBSD base, extract libs/includes and pkg keys
RUN mkdir /freebsd && \
	curl -Ls http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/i386/9.0-RELEASE/base.txz | \
		bsdtar -xf - -C /freebsd ./lib ./usr/lib ./usr/libdata ./usr/include ./etc

# Configure pkg (usage: pkg -r /freebsd install ...)
RUN mkdir -p /freebsd/usr/local/etc && \
	echo 'ABI = "FreeBSD:9:i386"; REPOS_DIR = ["/freebsd/etc/pkg"]; REPO_AUTOUPDATE = NO; RUN_SCRIPTS = NO;' > /freebsd/usr/local/etc/pkg.conf

ADD fix-links /freebsd/fix-links

RUN mkdir -p /usr/local/cross-compiler/i386-pc-freebsd9/ && \
    cp -a /freebsd/usr/include /usr/local/cross-compiler/i386-pc-freebsd9/ && \
    cp -a /freebsd/lib /usr/local/cross-compiler/i386-pc-freebsd9/ && \
    cp -a /freebsd/usr/lib/* /usr/local/cross-compiler/i386-pc-freebsd9/lib/ && \
    sh /freebsd/fix-links

# Install gcc to cross-compile
RUN apk add --no-cache gcc g++ file

ENV PATH /usr/local/cross-compiler/bin:/freebsd/bin/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN mkdir -p /src && \
    curl -Ls https://mirrors.sjtug.sjtu.edu.cn/gnu/binutils/binutils-2.25.1.tar.gz | bsdtar -xf - -C /src && \
    curl -Ls https://mirrors.sjtug.sjtu.edu.cn/gnu/gcc/gcc-5.5.0/gcc-5.5.0.tar.xz | bsdtar -xf - -C /src  && \
    curl -Ls https://mirrors.sjtug.sjtu.edu.cn/gnu/gmp/gmp-6.0.0a.tar.xz | bsdtar -xf - -C /src  && \
    curl -Ls https://mirrors.sjtug.sjtu.edu.cn/gnu/mpc/mpc-1.0.3.tar.gz | bsdtar -xf - -C /src  && \
    curl -Ls https://mirrors.sjtug.sjtu.edu.cn/gnu/mpfr/mpfr-3.1.3.tar.xz | bsdtar -xf - -C /src 

RUN cd /src/binutils-2.25.1 && \
    ./configure --enable-libssp --enable-ld --target=i386-pc-freebsd9 --prefix=/usr/local/cross-compiler/ && \
    make -j4 && \
    make install && \
    cd /src/gmp-6.0.0 && \
    ./configure --prefix=/usr/local/cross-compiler --enable-shared --enable-static \
      --enable-fft --enable-cxx --host=x86_64-pc-freebsd9 && \
    make -j4 && \
    make install && \
    cd /src/mpfr-3.1.3 && \
    ./configure --prefix=/usr/local/cross-compiler --with-gnu-ld  --enable-static \
      --enable-shared --with-gmp=/usr/local/cross-compiler --host=i386-pc-freebsd9 && \
    make -j4 && \
    make install && \
    cd /src/mpc-1.0.3/ && \
    ./configure --prefix=/usr/local/cross-compiler/ --with-gnu-ld \
      --enable-static --enable-shared --with-gmp=/usr/local/cross-compiler \
      --with-mpfr=/usr/local/cross-compiler --host=i386-pc-freebsd9  &&\
    make -j4 && \
    make install && \
    mkdir -p /src/gcc-5.5.0/build && \
    cd /src/gcc-5.5.0/build && \
    CFLAGS="-D__FUNCTION__=__func__ -Wno-switch -Wno-pedantic -Wno-switch-bool -Wno-unused-but-set-variable -Wno-c++-compat -Wno-misleading-indentation -Wno-shift-negative-value" \
    CXXFLAGS="-D__FUNCTION__=__func__ -Wno-literal-suffix -Wno-switch -Wno-pedantic -Wno-switch-bool -Wno-unused-but-set-variable -Wno-misleading-indentation -Wno-shift-negative-value" \
    ../configure --without-headers --with-gnu-as --with-gnu-ld --disable-nls \
        --enable-languages=c,c++ --enable-libssp --enable-ld \
        --disable-libitm --disable-libquadmath --disable-libcilkrts --target=i386-pc-freebsd9 \
        --prefix=/usr/local/cross-compiler/ --with-gmp=/usr/local/cross-compiler \
        --with-mpc=/usr/local/cross-compiler --with-mpfr=/usr/local/cross-compiler --disable-libgomp && \
    LD_LIBRARY_PATH=/usr/local/cross-compiler/lib make -j10 && \
    make install && \
    rm -rf /src

# Configure pkg-config
ENV PKG_CONFIG_LIBDIR /freebsd/usr/libdata/pkgconfig:/freebsd/usr/local/libdata/pkgconfig
ENV PKG_CONFIG_SYSROOT_DIR /freebsd

ENV LD_LIBRARY_PATH=/usr/local/cross-compiler/lib:/freebsd/lib:$LD_LIBRARY_PATH
