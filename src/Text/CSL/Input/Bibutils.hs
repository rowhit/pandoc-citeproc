{-# LANGUAGE CPP, ForeignFunctionInterface, PatternGuards #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Text.CSL.Input.Bibutils
-- Copyright   :  (C) 2008 Andrea Rossato
-- License     :  BSD3
--
-- Maintainer  :  andrea.rossato@unitn.it
-- Stability   :  unstable
-- Portability :  unportable
--
-----------------------------------------------------------------------------

module Text.CSL.Input.Bibutils
    ( readBiblioFile
    , readBiblioString
    , BibFormat (..)
    ) where

import Data.ByteString.Lazy.UTF8 ( fromString )
import Data.Char
import System.FilePath ( takeExtension )
import Text.CSL.Pickle
import Text.CSL.Reference
import Text.CSL.Input.Json
import Text.CSL.Input.MODS
import Text.JSON.Generic

#ifdef USE_BIBUTILS
import qualified Control.Exception as E
import Control.Exception ( bracket, catch )
import Control.Monad.Trans ( liftIO )
import System.FilePath ( (</>), (<.>) )
import System.IO.Error ( isAlreadyExistsError )
import System.Directory
import Text.Bibutils
#endif

-- | Read a file with a bibliographic database. The database format
-- is recognized by the file extension.
--
-- Supported formats are: @json@, @mods@, @bibtex@, @biblatex@, @ris@,
-- @endnote@, @endnotexml@, @isi@, @medline@, and @copac@.
readBiblioFile :: FilePath -> IO [Reference]
#ifdef USE_BIBUTILS
readBiblioFile f
    = case getExt f of
        ".mods"    -> readBiblioFile' f mods_in
        ".bib"     -> readBiblioFile' f biblatex_in
        ".bibtex"  -> readBiblioFile' f bibtex_in
        ".ris"     -> readBiblioFile' f ris_in
        ".enl"     -> readBiblioFile' f endnote_in
        ".xml"     -> readBiblioFile' f endnotexml_in
        ".wos"     -> readBiblioFile' f isi_in
        ".medline" -> readBiblioFile' f medline_in
        ".copac"   -> readBiblioFile' f copac_in
        ".json"    -> readJsonInput f
        ".native"  -> readFile f >>= return . decodeJSON
        _          -> error $ "citeproc: the format of the bibliographic database could not be recognized\n" ++
                              "using the file extension."

#else
readBiblioFile f
    | ".mods"   <- getExt f = readModsCollectionFile f
    | ".json"   <- getExt f = readJsonInput f
    | ".native" <- getExt f = readFile f >>= return . decodeJSON
    | otherwise             = error $ "citeproc: Bibliography format not supported.\n" ++
                                      "citeproc-hs was not compiled with bibutils support."
#endif

data BibFormat
    = Mods
    | Json
    | Native
#ifdef USE_BIBUTILS
    | Bibtex
    | BibLatex
    | Ris
    | Endnote
    | EndnotXml
    | Isi
    | Medline
    | Copac
#endif

readBiblioString :: BibFormat -> String -> IO [Reference]
readBiblioString b s
    | Mods      <- b = return $ readXmlString xpModsCollection (fromString s)
    | Json      <- b = return $ readJsonInputString s
    | Native    <- b = return $ decodeJSON s
#ifdef USE_BIBUTILS
    | Bibtex    <- b = go bibtex_in
    | BibLatex  <- b = go biblatex_in
    | Ris       <- b = go ris_in
    | Endnote   <- b = go endnote_in
    | EndnotXml <- b = go endnotexml_in
    | Isi       <- b = go isi_in
    | Medline   <- b = go medline_in
    | Copac     <- b = go copac_in
#endif
    | otherwise      = error "in readBiblioString"
#ifdef USE_BIBUTILS
    where
      go f = withTempDir "citeproc" $ \tdir -> do
               let tfile = tdir </> "bibutils-tmp.biblio"
               writeFile tfile s
               readBiblioFile' tfile f
#endif

#ifdef USE_BIBUTILS
readBiblioFile' :: FilePath -> BiblioIn -> IO [Reference]
readBiblioFile' fin bin
    | bin == mods_in = readModsCollectionFile fin
    | otherwise      = E.handle handleBibfileError
                       $ withTempDir "citeproc"
                       $ \tdir -> do
                            let tfile = tdir </> "bibutils-tmp"
                            param <- bibl_initparams bin mods_out "hs-bibutils"
                            bibl  <- bibl_init
                            unsetBOM        param
                            setCharsetIn    param bibl_charset_unicode
                            setCharsetOut   param bibl_charset_unicode
                            _ <- bibl_read  param bibl fin
                            _ <- bibl_write param bibl tfile
                            bibl_free bibl
                            bibl_freeparams param
                            refs <- readModsCollectionFile tfile
                            return $! refs
  where handleBibfileError :: E.SomeException -> IO [Reference]
        handleBibfileError e = error $ "Error reading " ++ fin ++ "\n" ++ show e

-- | Perform a function in a temporary directory and clean up.
withTempDir :: FilePath -> (FilePath -> IO a) -> IO a
withTempDir baseName = bracket (createTempDir 0 baseName)
  (removeDirectoryRecursive)

-- | Create a temporary directory with a unique name.
createTempDir :: Integer -> FilePath -> IO FilePath
createTempDir num baseName = do
  sysTempDir <- getTemporaryDirectory
  let dirName = sysTempDir </> baseName <.> show num
  liftIO $ Control.Exception.catch (createDirectory dirName >> return dirName) $
      \e -> if isAlreadyExistsError e
            then createTempDir (num + 1) baseName
            else ioError e
#endif

getExt :: String -> String
getExt = takeExtension . map toLower
