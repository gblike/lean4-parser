import Parser.Prelude
import Parser.Error
import Parser.Parser
import Parser.Stream

namespace Parser
variable {ε σ α β γ} [Parser.Stream σ α] [Parser.Error ε σ α] {m} [Monad m] [MonadExceptOf ε m]

/-- `tokenMap test` accepts token `t` with result `x` if `test t = some x`, otherise fails -/
@[specialize] def tokenMap (test : α → Option β) : ParserT ε σ α m β := do
  match Stream.next? (← StateT.get).stream with
  | some (x, s) =>
    StateT.set {stream := s, dirty := true}
    match test x with
    | some y => return y
    | none => throwUnexpected x
  | none => throwUnexpected

/-- `endOfInput` succeeds only when there is no input left -/
@[inline] def endOfInput : ParserT ε σ α m Unit := do
  match Stream.next? (← StateT.get).stream with
  | some (x, s) =>
    StateT.set {stream := s, dirty := true}
    throwUnexpected x
  | none => return

/-- `tokenFilter test` accepts and returns token `t` if `test t = true`, otherwise fails -/
@[inline] def tokenFilter (test : α → Bool) : ParserT ε σ α m α :=
  tokenMap fun c => if test c then some c else none

/-- `token tk` accepts and returns `tk`, otherwise fails -/
@[inline] def token [BEq α] (tk : α) : ParserT ε σ α m α :=
  tokenFilter (. == tk)

/-- `tokenArray tks` accepts and returns `tks`, otherwise fails -/
def tokenArray [BEq α] (tks : Array α) : ParserT ε σ α m (Array α) :=
  withBacktracking do
    let mut acc : Array α := #[]
    for tk in tks do
      acc := acc.push (← token tk)
    return acc

/-- `tokenList tks` accepts and returns `tks`, otherwise fails -/
def tokenList [BEq α] (tks : List α) : ParserT ε σ α m (List α) :=
  withBacktracking do
    let mut acc : Array α := #[]
    for tk in tks do
      acc := acc.push (← token tk)
    return acc.toList

/-- `lookAhead p` parses `p` without consuming any input -/
def lookAhead (p : ParserT ε σ α m β) : ParserT ε σ α m β := do
  let savePos ← getPosition
  try
    let x ← p
    setPosition savePos false
    return x
  catch e =>
    setPosition savePos false
    throw e

/-- `notFollowedBy p` succeeds only if `p` fails -/
@[inline] def notFollowedBy (p : ParserT ε σ α m β) : ParserT ε σ α m Unit :=
  try
    let _ ← lookAhead p
    throwUnexpected
  catch _ =>
    return

/-- `anyToken` accepts any single token and returns that token -/
@[inline] def anyToken : ParserT ε σ α m α :=
  tokenMap some

/-- `peek` returns the next token, without consuming any input -/
@[inline] def peek : ParserT ε σ α m α :=
  lookAhead anyToken

/-- `optionD default p` tries to parse `p`, and returns `default` if `p` fails -/
@[inline] def optionD (default : β) (p : ParserT ε σ α m β) : ParserT ε σ α m β :=
  try p catch _ => return default

/-- `option! p` tries to parse `p`, and returns `Inhabited.default` if `p` fails -/
@[inline] def option! [Inhabited β] (p : ParserT ε σ α m β) : ParserT ε σ α m β :=
  optionD default p

/-- `option? p` parses `p` returns `some x` if `p` returns `x`, and returns `none` if `p` fails -/
@[inline] def option? (p : ParserT ε σ α m β) : ParserT ε σ α m (Option β) :=
  option! (some <$> p)

/-- `optional p` tries to parse `p`, ignoring the output, never fails -/
@[inline] def optional (p : ParserT ε σ α m β) : ParserT ε σ α m Unit :=
  option! (p *> return)

@[specialize]
private partial def foldAux (f : γ → β → γ) (y : γ) (p : ParserT ε σ α m β) : ParserT ε σ α m γ :=
  let rec rest (y : γ) : ParserT ε σ α m γ :=
    try
      let x ← withBacktracking p
      rest (f y x)
    catch _ => return y
  rest y

/-- `foldl f q p` -/
@[inline] partial def foldl (f : γ → β → γ) (q : ParserT ε σ α m γ) (p : ParserT ε σ α m β) : ParserT ε σ α m γ := do
  foldAux f (← q) p

/-- `foldr f p q` -/
@[inline] partial def foldr (f : β → γ → γ) (p : ParserT ε σ α m β) (q : ParserT ε σ α m γ) : ParserT ε σ α m γ :=
  try
    let x ← withBacktracking p
    let y ← foldr f p q
    return f x y
  catch _ => q

/-- `take n p` parses exactly `n` occurrences of `p`, and returns an array of the returned values of `p` -/
@[inline] def take (n : Nat) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) :=
  let rec rest : Nat → Array β → ParserT ε σ α m (Array β)
  | 0, xs => return xs
  | n+1, xs => do
    let x ← p
    rest n (Array.push xs x)
  rest n #[]

/-- `takeUpTo n p` parses up to `n` occurrences of `p`, and returns an array of the returned values of `p` -/
@[inline] def takeUpTo (n : Nat) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) :=
  let rec rest : Nat → Array β → ParserT ε σ α m (Array β)
  | 0, xs => return xs
  | n+1, xs => try
      let x ← withBacktracking p
      rest n (Array.push xs x)
    catch _ => return xs
  rest n #[]

/-- `takeMany p` parses zero or more occurrences of `p` until it fails, and returns an array of the returned values of `p` -/
@[inline] def takeMany (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) := do
  foldAux Array.push #[] p

/-- `takeMany1 p` parses one or more occurrences of `p` until it fails, and returns an array of the returned values of `p` -/
@[inline] def takeMany1 (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) := do
  foldAux Array.push #[(← p)] p

/-- `takeManyN n p` parses `n` or more occurrences of `p` until it fails, and returns an array of the returned values of `p` -/
@[inline] def takeManyN (n : Nat) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) := do
  foldAux Array.push (← take n p) p

/-- `takeUntil stop p` parses zero or more occurrences of `p` until `stop` succeeds, and returns an array of the returned values of `p` and the output of `stop` -/
@[inline] def takeUntil (stop : ParserT ε σ α m γ) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β × γ) := do
  return (← takeMany (notFollowedBy stop *> p), ← stop)

/-- `drop n p` parses exactly `n` occurrences of `p`, ignoring all outputs from `p` -/
@[inline] def drop (n : Nat) (p : ParserT ε σ α m β) : ParserT ε σ α m Unit :=
  match n with
  | 0 => return
  | n+1 => do
      let _ ← p
      drop n p

/-- `dropUpto n p` parses up to `n` occurrences of `p`, ignoring all outputs from `p` -/
@[inline] def dropUpTo (n : Nat) (p : ParserT ε σ α m β) : ParserT ε σ α m Unit :=
  match n with
  | 0 => return
  | n+1 => try
      let _ ← withBacktracking p
      drop n p
    catch _ => return

/-- `dropMany p` parses zero or more occurrences of `p` until it fails, ignoring all outputs from `p` -/
@[inline] def dropMany (p : ParserT ε σ α m β) : ParserT ε σ α m Unit :=
  foldAux (Function.const β) () p

/-- `dropMany1 p` parses one or more occurrences of `p` until it fails, ignoring all outputs from `p` -/
@[inline] def dropMany1 (p : ParserT ε σ α m β) : ParserT ε σ α m Unit :=
  p *> foldAux (Function.const β) () p

/-- `dropManyN n p` parses `n` or more occurrences of `p` until it fails, ignoring all outputs from `p` -/
@[inline] def dropManyN (n : Nat) (p : ParserT ε σ α m β) : ParserT ε σ α m Unit :=
  drop n p *> foldAux (Function.const β) () p

/-- `dropUntil stop p` runs `p` until `stop` succeeds, returns the output of `stop` ignoring all outputs from `p` -/
@[inline] def dropUntil (stop : ParserT ε σ α m γ) (p : ParserT ε σ α m β) : ParserT ε σ α m γ :=
  dropMany (notFollowedBy stop *> p) *> stop

/-- `sepBy1 p sep` parses one or more occurrences of `p`, separated by `sep`, returns an array of values returned by `p` -/
@[inline] def sepBy1 (sep : ParserT ε σ α m Unit) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) := do
  foldAux Array.push #[← withBacktracking p] (sep *> p)

/-- `sepBy p sep` parses zero or more occurrences of `p`, separated by `sep`, returns an array of values returned by `p` -/
@[inline] def sepBy (sep : ParserT ε σ α m Unit) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) :=
  sepBy1 sep p <|> return #[]

/-- `endBy p sep` parses zero or more occurrences of `p`, separated and ended by `sep`, returns an array of values returned by `p` -/
@[inline] def endBy (sep : ParserT ε σ α m Unit) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) :=
  takeMany (p <* sep)

/-- `endBy1 p sep` parses one or more occurrences of `p`, separated and ended by `sep`, returns an array of values returned by `p` -/
@[inline] def endBy1 (sep : ParserT ε σ α m Unit) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) := do
  takeMany1 (p <* sep)

/-- `sepEndBy1 p sep` parses one or more occurrences of `p`, separated and optionally ended by `sep`, returns an array of values returned by `p` -/
@[inline] def sepEndBy1 (sep : ParserT ε σ α m Unit) (p : ParserT ε σ α m β) : ParserT ε σ α m (Array β) :=
  sepBy1 sep p <* optional sep

/-- `sepEndBy p sep` parses zero or more occurrences of `p`, separated and optionally ended by `sep`, returns an array of values returned by `p` -/
@[inline] def sepEndBy (sep : ParserT ε σ α m Unit) (p : ParserT ε σ α m α) : ParserT ε σ α m (Array α) :=
  sepEndBy1 sep p <|> return #[]

end Parser
