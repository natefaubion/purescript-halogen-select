module Main where

import Prelude

import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Exception (EXCEPTION)
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Typeahead (component, TEffects)

type MainEffects =
  ( exception :: EXCEPTION
  | TEffects ()
  )

main :: Eff MainEffects Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  runUI component unit body
