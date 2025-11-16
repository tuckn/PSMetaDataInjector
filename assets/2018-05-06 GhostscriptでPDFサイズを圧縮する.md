## 圧縮
* diff-pdfの結果のPDFがでかい！
* サイズを小さくしたい

https://gist.github.com/firstdoit/6390547

Ghostscriptでできる？

```
gswin64c.exe  -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/printer -dNOPAUSE -dQUIET -dBATCH -sOutputFile=diff-output.pdf diff.pdf
```

* これでできた！
* 50.36MBが19.59MBになった

> This can reduce files to ~15% of their size (2.3M to 345K, in one case) with no obvious degradation of quality.

* と書かれているように、パッと見た目にも劣化はわからない
