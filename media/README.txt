KickCD media assets
===================

Required files (consumed by KickCD.toc and the runtime modules):

  icon.tga             64x64 addon icon shown in WoW's addon list.
                       Referenced by `## IconTexture: Interface\AddOns\KickCD\media\icon`.
  statusbar-flat.tga   1x8 flat texture used as the default castbar fill.
                       WoW tints this at runtime via `StatusBar:SetStatusBarColor`.

Format
------

Both files are uncompressed 24-bit TGA (image type 2), top-left origin.
WoW expects Targa, BLP, or PNG for `## IconTexture`; TGA is the simplest
to ship as source-controllable artwork.

Current contents (v0.1 placeholders)
------------------------------------

  icon.tga             64x64 solid green (rgb 0,255,100). Generated via
                       `printf` byte-stream because no ImageMagick / GIMP
                       was available in the build environment. Replace
                       with branded artwork (a green "K" on dark navy is
                       the design intent) when convenient.
  statusbar-flat.tga   1x8 solid white. Generated the same way.

License
-------

The placeholder TGAs in this folder are original artwork created for the
KickCD project and are licensed under the MIT license, the same as the
rest of the addon (see ../LICENSE). No third-party assets are bundled.
