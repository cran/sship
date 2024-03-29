#' Unpack shipment and decrypt content
#'
#' This function tries to reverse the process of \link{enc} and hence depend on
#' the conventions used there.
#'
#' Some of the functions used here might be vulnerable to differences between
#' systems running R. Possible caveats may be the availability of the
#' (un)tar-function and how binary streams/files are treated.
#'
#' @param tarfile Character string providing full path to the gzip-compressed
#'   tarball holding the shipment payload, including encrypted files.
#' @param keyfile Character string providing the full path to the private RSA
#'   key to be used for decryption of the encrypted key that is part of the
#'   shipment. Default value is set to \code{~/.ssh/id_rsa} which is the usual
#'   path for unix type operating systems.
#' @param target_dir Character string providing the full path to where the
#'   decrypted file is to be written. Defaults to the current directory
#'   \code{"."}, \emph{e.g.} where this function is being called from.
#'
#' @return Invisibly a character string providing the file path of the
#'   decrypted file.
#'
#' @seealso \link{enc}
#' @export
#' @examples
#' # Please note that these examples will write files to a local temporary
#' # directory.
#'
#' ## Make temporary workspace
#' wd <- tempdir()
#'
#' ## Make a private-public key pair named "id_rsa" and "id_rsa.pub"
#' keygen(directory = wd, type = "rsa", overwrite_existing = TRUE)
#'
#' ## Make a secured (encrypted) file
#' saveRDS(iris, file = file.path(wd, "secret.rds"), ascii = TRUE)
#' pubkey <- readLines(file.path(wd, "id_rsa.pub"))
#' secure_secret_file <-
#'   enc(filename = file.path(wd, "secret.rds"),
#'       pubkey_holder = NULL,
#'       pubkey = pubkey)
#'
#' ## Decrypt secured file using the private key
#' secret_file <-
#'   dec(tarfile = secure_secret_file,
#'       keyfile = file.path(wd, "id_rsa"),
#'       target_dir = wd)

dec <- function(tarfile, keyfile = "~/.ssh/id_rsa", target_dir = ".") {

  tarfile <- normalizePath(tarfile)
  keyfile <- normalizePath(keyfile)
  target_dir <- normalizePath(target_dir)

  prikey <- openssl::read_key(keyfile)
  stopifnot(inherits(prikey, "rsa"))

  init_dir <- getwd()
  on.exit(setwd(init_dir))
  setwd(tempdir())

  # by internal convention, first part of tarfile name is actual file name
  target_file <- file.path(normalizePath(target_dir),
                           strsplit(basename(tarfile), "__")[[1]][1])

  source_file <- enc_filename(basename(target_file))
  symkey_file <- enc_filename("key")

  untar(tarfile, tar = "internal")

  iv <- readBin("iv", raw(), file.info("iv")$size)
  enc_key <- readBin(symkey_file, raw(), file.info(symkey_file)$size)
  enc_msg <- readBin(source_file, raw(), file.info(source_file)$size)

  key <- openssl::rsa_decrypt(enc_key, prikey)
  msg <- sym_dec(enc_msg, key, iv)

  writeBin(msg, basename(target_file))

  # clean up and move back to initial dir
  file.copy(basename(target_file), target_file)
  file.remove(c("iv", symkey_file, source_file, basename(target_file)))

  message(paste("sship: Decrypted file written to", target_file))

  invisible(target_file)

}


#' Standard sship symmetric decryption
#'
#' @param data raw vector or path to file with data to encrypt or decrypt
#' @param key raw vector of length 16, 24 or 32, e.g. the hash of a shared
#'   secret
#' @param iv raw vector of length 16 (aes block size) or NULL. The
#'   initialization vector is not secret but should be random
#'
#' @return A raw vector of decrypted \code{data}.
#' @keywords internal
#' @export

sym_dec <- function(data, key, iv = attr(data, "iv")) {

  openssl::aes_cbc_decrypt(data, key, iv)
}

