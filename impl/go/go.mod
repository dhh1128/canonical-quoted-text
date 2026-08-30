module github.com/dhh1128/canonical-quoted-text

// CQT 3.17 requires Unicode 17.0.0 data. Go ships 15.0.0 through go1.26 and
// 17.0.0 from go1.27, in the standard library and in the x/text normalizer
// alike, so the toolchain floor is part of the algorithm's correctness rather
// than a matter of taste.
go 1.27

require golang.org/x/text v0.41.0
