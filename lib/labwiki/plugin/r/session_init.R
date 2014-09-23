LW <- list()
LW$tf <- tempfile(pattern = "plot", fileext = ".svg")
LW$valid_classes <- c("numeric", "integer", "complex", "character", "list", "data.frame", "try-error", "help_files_with_topic")
LW$envir = new.env(parent = globalenv())
LW$eval <- function(s, width = 7, height = 7, pointsize = 12) {
  if (file.exists(LW$tf)) {
    file.remove(LW$tf)
  }
  svg(filename = LW$tf, width = width, height = height, pointsize = pointsize)
  t <- try(eval(parse(text=s), envir=LW$envir), silent = TRUE)
  l <- list(class = class(t), type = typeof(t))
  if (class(t) %in% LW$valid_classes) {
    l$msg = t
  }
  dev.off()
  if (file.exists(LW$tf)) {
    l$svg = readChar(LW$tf, file.info(LW$tf)$size)
  }
  return(l)
}
version$version.string
