use ExtUtils::MakeMaker;

WriteMakefile
(
 NAME => "Mail::POP3Client",
 DISTNAME => "POP3Client",
 
 VERSION_FROM =>  "POP3Client.pm",
 
 dist         => {
     COMPRESS  => "gzip -9f",
     SUFFIX    => "gz",
 }
);
