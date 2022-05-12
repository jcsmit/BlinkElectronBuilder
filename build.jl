# This solution is based on ElectronBuilder by davidanthoff
# https://github.com/davidanthoff/ElectronBuilder

using Pkg.Artifacts
using Pkg.BinaryPlatforms
using URIParser
using FilePaths

pkgname = "BlinkElectron"
version = v"4.0.4"
buildnr = 0

build_path = joinpath(@__DIR__, "build")

if ispath(build_path)
    rm(build_path, force = true, recursive = true)
end

mkpath(build_path)

artifact_toml = joinpath(build_path, "Artifacts.toml")

platforms = [
    # Linux
    Linux(:x86_64),
    Linux(:i686),

    # MacOS
    MacOS(:x86_64),

    # Windows
    Windows(:x86_64),
    Windows(:i686),
]

download_url_root = "https://github.com/electron/electron/releases/download"

publish_url_root = "https://github.com/jcsmit/BlinkElectronBuilder/releases/download"

mktempdir() do tmp_dir
    for platform in platforms
        if platform isa Linux && arch(platform) == :x86_64
            os_arch = "linux-x64"
        elseif platform isa Linux && arch(platform) == :i686
            os_arch = "linux-ia32"
        elseif platform isa MacOS && arch(platform) == :x86_64
            os_arch = "darwin-x64"
        elseif platform isa Windows && arch(platform) == :x86_64
            os_arch = "win32-x64"
        elseif platform isa Windows && arch(platform) == :i686
            os_arch = "win32-ia32"
        end

        download_url = "$download_url_root/v$version/electron-v$version-$os_arch.zip"

        download_filename = joinpath(Path(tmp_dir), Path(basename(URI(download_url).path)))

        download(download_url, download_filename)

        artifact_hash = create_artifact() do artifact_dir
            download("http://junolab.s3.amazonaws.com/blink/julia.png", joinpath(artifact_dir, "julia.png"))

            cmd = if extension(download_filename) == "zip"
                Cmd(`unzip $download_filename -d $artifact_dir`)
            else
                Cmd(`tar -xvf $download_filename -C $artifact_dir`)
            end
            run(cmd)

            # Ensure that all the files are in the root folder
            files = readdir(artifact_dir)
            if length(files) == 1
                files_to_move = readdir(joinpath(artifact_dir, files[1]))
                for file in files_to_move
                    mv(joinpath(artifact_dir, files[1], file), joinpath(artifact_dir, file))
                end
                rm(joinpath(artifact_dir, files[1]), force = true)
            end

            if platform isa MacOS
                cd(artifact_dir) do                    
                    run(`mv Electron.app Julia.app`)
                    run(`mv Julia.app/Contents/MacOS/Electron Julia.app/Contents/MacOS/Julia`)
                    run(`sed -i.bak 's/Electron/Julia/' Julia.app/Contents/Info.plist`)
                    cp(joinpath(@__DIR__, "res", "julia-icns.icns"), "Julia.app/Contents/Resources/electron.icns", force = true)
                    run(`touch Julia.app`)  # Apparently this is necessary to tell the OS to double-check for the new icons.
                end
            end

            if platform isa Windows
                for (root, dirs, files) in walkdir(artifact_dir)
                    cd(root) do
                        for file in files
                            run(`chmod u+x "$file"`)
                        end
                    end
                end
            end
        end

        archive_filename = "$pkgname-$version+$buildnr-$(triplet(platform)).tar.gz"

        download_hash = archive_artifact(artifact_hash, joinpath(build_path, archive_filename))

        bind_artifact!(
            artifact_toml,
            "$(pkgname)_app",
            artifact_hash,
            platform = platform,
            force = true,
            download_info = Tuple[(
                "$publish_url_root/v$(URIParser.escape(string(version) * "+" * string(buildnr)))/$archive_filename",
                download_hash,
            )],
        )
    end
end
