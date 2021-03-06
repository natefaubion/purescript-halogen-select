module Calendar where

import Prelude
import Calendar.Utils (alignByWeek, nextMonth, nextYear, prevMonth, prevYear, rowsFromArray, unsafeMkYear, unsafeMkMonth)
import CSS as CSS
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Console (log)
import Control.Monad.Eff.Now (NOW, now)
import Data.Array (mapWithIndex)
import Data.Date (Date, Month, Year, canonicalDate, month, year)
import Data.DateTime (date)
import Data.DateTime.Instant (fromDate, toDateTime)
import Data.Either (either)
import Data.Formatter.DateTime (formatDateTime)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Monoid (mempty)
import Data.Tuple (Tuple(..), fst, snd)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.CSS as HC
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Select.Primitives.Container as C
import Select.Effects (Effects)


{-

The calendar component is an example.

-}

type State =
  { targetDate :: Tuple Year Month }

data Query a
  = HandleContainer (C.Message Query CalendarItem) a
  | ToContainer (C.ContainerQuery Query CalendarItem Unit) a
  | ToggleYear  Direction a
  | ToggleMonth Direction a
  | SetTime a

data Direction = Prev | Next

type FX e = Aff (CalendarEffects e)
type CalendarEffects e = (Effects (now :: NOW | e))
type ParentHTML e = H.ParentHTML Query ChildQuery Unit (FX e)
type ChildQuery = C.ContainerQuery Query CalendarItem

----------
-- Calendar Items
data CalendarItem
  = CalendarItem SelectableStatus SelectedStatus BoundaryStatus Date

data SelectableStatus
  = NotSelectable
  | Selectable

data SelectedStatus
  = NotSelected
  | Selected

data BoundaryStatus
  = OutOfBounds
  | InBounds


component :: ∀ e. H.Component HH.HTML Query Unit Void (FX e)
component =
  H.lifecycleParentComponent
    { initialState
    , render
    , eval
    , receiver: const Nothing
    , initializer: Just (H.action SetTime)
    , finalizer: Nothing
    }
  where
    initialState :: Unit -> State
    initialState = const
      { targetDate: Tuple (unsafeMkYear 2019) (unsafeMkMonth 2) }

    eval :: Query ~> H.ParentDSL State Query ChildQuery Unit Void (FX e)
    eval = case _ of
      ToContainer q a -> H.query unit q *> pure a

      HandleContainer m a -> case m of
        C.Emit q -> eval q *> pure a

        C.ItemSelected item -> a <$ do
          let showCalendar (CalendarItem _ _ _ d) = show d
          H.liftAff $ log ("Selected! Choice was " <> showCalendar item)

      ToggleMonth dir a -> a <$ do
        st <- H.get

        let y = fst st.targetDate
            m = snd st.targetDate

        let newDate = case dir of
               Next -> nextMonth (canonicalDate y m bottom)
               Prev -> prevMonth (canonicalDate y m bottom)

        H.modify _ { targetDate = Tuple (year newDate) (month newDate) }

      ToggleYear dir a -> a <$ do
        st <- H.get

        let y = fst st.targetDate
            m = snd st.targetDate

        let newDate = case dir of
               Next -> nextYear (canonicalDate y m bottom)
               Prev -> prevYear (canonicalDate y m bottom)

        H.modify _ { targetDate = Tuple (year newDate) (month newDate) }

      SetTime a -> do
         x <- H.liftEff now
         let d = date (toDateTime x)
         H.modify _ { targetDate = Tuple (year d) (month d) }
         pure a


    render :: State -> H.ParentHTML Query ChildQuery Unit (FX e)
    render st =
      HH.div
        [ HP.class_ $ HH.ClassName "mw8 sans-serif center" ]
        [ HH.h2
          [ HP.class_ $ HH.ClassName "black-80 f-headline-1" ]
          [ HH.text "Calendar Component"]
        , renderToggle
        , HH.slot
            unit
            C.component
            { items: generateCalendarRows targetYear targetMonth
            , render: renderContainer targetYear targetMonth
            }
            ( HE.input HandleContainer )
        ]

      where
        targetYear  = fst st.targetDate
        targetMonth = snd st.targetDate

        renderToggle :: H.ParentHTML Query ChildQuery Unit (FX e)
        renderToggle =
          HH.span
          ( C.getToggleProps ToContainer
            [ HP.class_ $ HH.ClassName "f5 link ba bw1 ph3 pv2 mb2 dib near-black pointer outline-0" ]
          )
          [ HH.text "Toggle" ]

        -- The user is using the Container primitive, so they have to fill out a Container render function
        renderContainer :: Year -> Month -> (C.ContainerState CalendarItem) -> H.HTML Void ChildQuery
        renderContainer y m cst =
          HH.div_
            $ if not cst.open
              then [ ]
              else [ renderCalendar ]
          where
            fmtMonthYear = (either (const "-") id) <<< formatDateTime "MMMM YYYY" <<< toDateTime <<< fromDate
            monthYear = fmtMonthYear (canonicalDate y m bottom)

            renderCalendar :: H.HTML Void ChildQuery
            renderCalendar =
              HH.div
                ( C.getContainerProps
                  [ HP.class_ $ HH.ClassName "tc"
                  , HC.style  $ CSS.width (CSS.rem 28.0) ]
                )
                [ calendarNav
                , calendarHeader
                , HH.div_ $ renderRows $ rowsFromArray cst.items
                ]

            -- Given a string ("Month YYYY"), creates the calendar navigation
            calendarNav :: H.HTML Void ChildQuery
            calendarNav =
              HH.div
              [ HP.class_ $ HH.ClassName "flex pv3" ]
              [ arrowButton (ToggleYear Prev) "<<" (Just "ml2")
              , arrowButton (ToggleMonth Prev) "<" Nothing
              , dateHeader
              , arrowButton (ToggleMonth Next) ">" Nothing
              , arrowButton (ToggleYear Next) ">>" (Just "mr2")
              ]
              where
                arrowButton q t css =
                  HH.button
                  ( C.getChildProps
                    [ HP.class_ $ HH.ClassName $ "w-10" <> fromMaybe "" (((<>) " ") <$> css)
                    , HE.onClick $ HE.input_ $ C.Raise $ H.action q ]
                  )
                  [ HH.text t ]

                -- Show the month and year
                dateHeader =
                  HH.div
                  [ HP.class_ $ HH.ClassName "w-60 b" ]
                  [ HH.text monthYear ]

            calendarHeader =
              HH.div
              [ HP.class_ $ HH.ClassName "flex pv3" ]
              ( headers <#> (\day -> HH.div [ HP.class_ $ HH.ClassName "w3" ] [ HH.text day ]) )
              where
                headers = [ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" ]

            renderRows :: Array (Array CalendarItem) -> Array (H.HTML Void ChildQuery)
            renderRows = mapWithIndex (\row subArr -> renderRow (row * 7) subArr)
              where
                renderRow :: Int -> Array CalendarItem -> H.HTML Void ChildQuery
                renderRow offset items =
                  HH.div
                    [ HP.class_ $ HH.ClassName "flex" ]
                    ( mapWithIndex (\column item -> renderItem (column + offset) item) items )

            renderItem :: Int -> CalendarItem -> H.HTML Void ChildQuery
            renderItem index item =
              HH.div
                -- Use raw style attribute for convenience.
                ( attachItemProps index item
                [ HP.class_ $ HH.ClassName $ "w3 pa3" <> (if cst.highlightedIndex == Just index then " bg-washed-green" else "")
                , HP.attr (H.AttrName "style") (getCalendarStyles item) ]
                )
                [ HH.text $ printDay item ]
              where
                -- If the calendar item is selectable, augment the props with the correct click events.
                attachItemProps i (CalendarItem Selectable _ _ _) props = C.getItemProps i props
                attachItemProps _ _ props = props

                -- Get the correct styles for a calendar item dependent on its statuses
                getCalendarStyles :: CalendarItem -> String
                getCalendarStyles i
                  =  getSelectableStyles i
                  <> " " <> getSelectedStyles i
                  <> " " <> getBoundaryStyles i
                  where
                    getSelectableStyles:: CalendarItem -> String
                    getSelectableStyles (CalendarItem NotSelectable _ _ _)
                      = "color: rgba(0,0,0,0.6); background-image: linear-gradient(to bottom, rgba(125,125,125,0.75) 0%, rgba(125,125,125,0.75), 100%;"
                    getSelectableStyles _ = mempty

                    getSelectedStyles :: CalendarItem -> String
                    getSelectedStyles (CalendarItem _ Selected _ _) = "color: white; background-color: green;"
                    getSelectedStyles _ = mempty

                    getBoundaryStyles :: CalendarItem -> String
                    getBoundaryStyles (CalendarItem _ _ OutOfBounds _) = "opacity: 0.5;"
                    getBoundaryStyles _ = mempty

                printDay :: CalendarItem -> String
                printDay (CalendarItem _ _ _ d) = printDay' d
                  where
                    printDay' :: Date -> String
                    printDay' = (either (const "-") id)
                      <<< formatDateTime "D"
                      <<< toDateTime
                      <<< fromDate


{-

Helpers

-}

-- Generate a standard set of dates from a year and month.
generateCalendarRows :: Year -> Month -> Array CalendarItem
generateCalendarRows y m = lastMonth <> thisMonth <> nextMonth
  where
    { pre, body, post, all } = alignByWeek y m
    outOfBounds = map (\i -> CalendarItem Selectable NotSelected OutOfBounds i)
    lastMonth   = outOfBounds pre
    nextMonth   = outOfBounds post
    thisMonth   = body <#> (\i -> CalendarItem Selectable NotSelected InBounds i)

