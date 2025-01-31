{-# LANGUAGE CPP #-}
-- |
-- Module:      SHC.Stack
-- Copyright:   (c) 2014-2015 Guillaume Nargeot, (c) 2015-2016 Felipe Lessa
-- License:     BSD3
-- Maintainer:  Michele Lacchia <michelelacchia@gmail.com>
-- Stability:   experimental
--
-- Utility functions related to Stack.

module SHC.Stack
    where

import Data.Version
#if __GLASGOW_HASKELL__ < 710
import Control.Applicative ((<$>), (<*>))
#endif
import Control.Monad (forM, guard)
import Data.List (elem)
import System.Directory (makeRelativeToCurrentDirectory)
import System.FilePath ((</>), equalFilePath, splitPath)

import qualified Data.ByteString.Char8 as BS8
import qualified Data.Yaml as Y

import SHC.Types
import SHC.Utils

-- | A simple flag to signify what type of Stack call we need.
data StackNixUsage
    = StackUseNix
    | StackDoNotUseNix
    deriving (Eq, Show)

stack :: [String] -> IO String
stack = readP "stack"

-- | Verify that the required Stack is present.
checkStackVersion :: IO Bool
checkStackVersion = do
    let lowerBound = Version [0,1,7,0] []
    stackVersion <- stack ["--numeric-version"]
    return $ verifyVersion stackVersion lowerBound

-- | Return the HPC data directory, given the package name.
getHpcDir :: String -> IO FilePath
getHpcDir package = (</> package) <$> stack ["path", "--local-hpc-root"]

-- | Return the HPC mix directory, where module data is stored.  This
-- path needs to be prefixed with the project's path
-- (cf. 'stackProjectPath').
getBaseMixDir :: StackNixUsage -> IO FilePath
getBaseMixDir StackUseNix       = (</> "hpc") <$> stack ["path", "--dist-dir", "--nix"]
getBaseMixDir StackDoNotUseNix  = (</> "hpc") <$> stack ["path", "--dist-dir"]

-- | Get relevant information from @stack query@.  Used to find
-- package filepaths.
getStackQuery :: IO StackQuery
getStackQuery = (Y.decodeEither' . BS8.pack <$> stack ["query"]) >>= either err return
  where err = fail . (++) "getStackQuery: Couldn't decode the result of 'stack query' as YAML: " . show

-- | Get the key that GHC uses for the given package.
-- "stack exec -- ghc-pkg field cardano-shell key --simple-output"
getProjectKey :: String -> IO String
getProjectKey pkgName = stack ["exec", "--", "ghc-pkg", "field", pkgName, "key", "--simple-output"]


-- | Get the Stack info needed to find project files.
getStackProjects :: StackNixUsage -> IO [StackProject]
getStackProjects stackNixUsage = do
  sq            <- getStackQuery
  baseMixDir    <- getBaseMixDir stackNixUsage

  forM (stackQueryLocals sq) $ \(pkgName, filepath) -> do
    relfp <- makeRelativeToCurrentDirectory filepath
    let mpath = guard (not $ relfp `equalFilePath` ".") >> Just relfp
    key <- if ".stack-work/" `elem` splitPath relfp
             then return pkgName
             else getProjectKey pkgName
    return
      StackProject
        { stackProjectName   = pkgName
        , stackProjectPath   = mpath
        , stackProjectKey    = key
        , stackProjectMixDir = maybe id (</>) mpath baseMixDir
        }
