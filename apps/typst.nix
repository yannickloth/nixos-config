{ pkgs, ... }:

let
  typstPackages = with pkgs; [
    tinymist # Tinymist is an integrated language service for Typst
    typst # New markup-based typesetting system that is powerful and easy to learn
    typstyle # Format your typst source code
    texlivePackages.pdfbook2 # Create booklets from PDF files
  ];
in
{
  environment.systemPackages = typstPackages;
}
