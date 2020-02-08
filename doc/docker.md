# Use docker to generate the openfang firmware and toolchain
Docker is well known among software developers. Even if you are not familiar with it, you can easily follow the build procedure in just a few small steps. We recommend starting with the first option.


## Build openfang using pre-built Docker image (recommended)
To retrieve the image from Docker Hub and use it to compile the latest development version of openfang:

```bash
docker run -it -v $(pwd)/output:/output anmaped/openfang
```

Now the image files containing the openfang bootloader and rootfs are in the current directory.


## Build openfang from git repository
To build a local version of openfang:

```bash
docker build -t openfang .
docker run -it -v $(pwd)/output:/output openfang
```
