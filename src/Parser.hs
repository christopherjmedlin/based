module Parser (module Parser) where

import Text.Parsec
import Text.Parsec.String
import Expr
import Control.Monad
import Data.Char
import Data.Map hiding (foldr, take)
import Data.List (sort, sortOn)

consumeUntil :: Char -> Parser String
consumeUntil u = do
    c <- anyChar
    if c == u 
        then 
            return [] 
        else do
            x <- consumeUntil u
            return (c : x)

commaSep :: Parser a -> Parser [a]
commaSep p = p `sepBy` ((many (char ' ')) >> char ',' >> (many (char  ' ')))

integer :: Parser Integer
integer = read <$> many1 digit

float :: Parser Double
float = read <$> do
    d1 <- many1 digit
    c <- char '.'
    d2 <- many1 digit
    return $ d1 ++ [c] ++ d2

anyString :: Parser String
anyString = many1 anyChar

numExpr :: Parser Aexpr
numExpr = NumExpr <$> integer

floatExpr :: Parser Aexpr
floatExpr = FloatExpr <$> float

anyAlpha :: Parser Char
anyAlpha = do
    c <- anyChar
    guard (isAlpha c)
    return c

varExpr :: Parser Aexpr
varExpr = VarExpr <$> anyAlpha

emptyParser = do { fail ""; }

-- parses a binary operation. c is the character symbolizing the operation,
-- cons is the data constructor (e.g. SumExpr), left is the list of allowed
-- expressions on the left, right is the list of allowed expressions on the
-- right
bop :: Char -> (Aexpr -> Aexpr -> Aexpr) -> [Parser Aexpr] 
                                         -> [Parser Aexpr] 
                                         -> Parser Aexpr
bop c cons left right= do
    a1 <- Prelude.foldr (<|>) emptyParser (fmap try left)
    spaces
    char c
    spaces
    a2 <- Prelude.foldr (<|>) emptyParser (fmap try right)
    return $ cons a1 a2

-- being the last in the order of operations, any expression can be on the
-- right or left, as it will take precedence and should be evaluated first. the
-- exception is diffExpr itself, we cannot have left recursion
diffExpr = bop '-' DiffExpr
           [sumExpr, divExpr, prodExpr, simpleAexpr]
           [aexpr]

sumExpr = bop '+' SumExpr
          [divExpr, prodExpr, simpleAexpr]
          [sumExpr, divExpr, prodExpr, simpleAexpr]

divExpr = bop '/' DivExpr
          [prodExpr, simpleAexpr]
          [divExpr, prodExpr, simpleAexpr]

prodExpr = bop '*' ProdExpr
           [simpleAexpr]
           [prodExpr, simpleAexpr]

simpleAexpr = aexprParens <|> try func <|> negExpr <|> try floatExpr 
              <|> try numExpr <|> try arrExpr <|> try varExpr

aexprParens :: Parser Aexpr
aexprParens = do
    char '('
    spaces
    a <- aexpr
    spaces
    char ')'
    return a

funcs = string "INT" <|> string "RND"

nameToFunc :: String -> (Aexpr -> Aexpr)
nameToFunc "INT" = IntExpr
nameToFunc "RND" = RndExpr

func :: Parser Aexpr
func = do
    name <- funcs
    aexpr <- aexprParens
    return $ nameToFunc name aexpr

negExpr :: Parser Aexpr
negExpr = do
    char '-'
    a <- try func <|> try aexprParens <|> try floatExpr <|> numExpr <|> varExpr
    return $ ProdExpr (NumExpr (-1)) a

to4Tup :: [a] -> a -> (a,a,a,a)
to4Tup [] def = (def,def,def,def)
to4Tup [x] def = (x,def,def,def)
to4Tup [x1, x2] def = (x1,x2,def,def)
to4Tup [x1, x2, x3] def = (x1,x2,x3,def)
to4Tup [x1, x2, x3, x4] def = (x1,x2,x3,x4)
to4Tup x def = to4Tup (take 4 x) def

arrExpr :: Parser Aexpr
arrExpr = do
    c <- anyChar
    char '('
    as <- commaSep aexpr
    char ')'
    return $ ArrExpr c (to4Tup as (NumExpr 0))

aexpr :: Parser Aexpr
aexpr = try diffExpr <|> try sumExpr <|> try divExpr <|> try prodExpr 
        <|> simpleAexpr
        
toStringExpr :: Parser Sexpr
toStringExpr = do
    a <- aexpr
    return $ ToStringExpr a

literalExpr :: Parser Sexpr
literalExpr = LiteralExpr <$> (char '"' >> consumeUntil '"')

concatExpr :: Parser Sexpr
concatExpr = ConcatExpr <$> left <*> normalSexpr
    where left = do
            s <- toStringExpr <|> literalExpr
            char ';'
            many (char ' ')
            return s

normalSexpr = try concatExpr <|> toStringExpr <|> literalExpr

-- a Sexpr followed by a ';'
noNewLineExpr :: Parser Sexpr
noNewLineExpr = do
    s <- try concatExpr <|> toStringExpr <|> literalExpr
    char ';'
    return $ NoNewLineExpr s

sexpr :: Parser Sexpr
sexpr = try noNewLineExpr <|> normalSexpr

strToComp :: String -> (Aexpr -> Aexpr -> Bexpr)
strToComp "=" = EqExpr
strToComp ">" = GeExpr
strToComp "<" = LeExpr
strToComp "<>" = NeqExpr

bexpr :: Parser Bexpr
bexpr = do
    a1 <- aexpr
    spaces
    c <- string "=" <|> try (string "<>") <|> string "<" <|> string ">"
    spaces
    a2 <- aexpr
    return $ (strToComp c) a1 a2

letCom :: Parser Com
letCom = do
    string "LET"
    spaces
    c <- try arrExpr <|> varExpr
    spaces
    char '='
    spaces
    e <- aexpr
    return $ LetCom c e

printCom :: Parser Com
printCom = do
    string "PRINT"
    spaces
    s <- sexpr
    return $ PrintCom s

endCom :: Parser Com
endCom = do {string "END"; return EndCom}

gotoCom :: Parser Com
gotoCom = do
    string "GOTO"
    spaces
    i <- integer
    return $ GotoCom i

ifCom :: Parser Com
ifCom = do
    string "IF"
    spaces
    b <- bexpr
    spaces
    string "THEN"
    spaces
    i <- integer
    return $ IfCom b i

forCom :: Parser Com
forCom = do
    string "FOR"
    spaces
    c <- anyChar
    spaces
    char '='
    spaces
    a1 <- aexpr
    spaces
    string "TO"
    spaces
    a2 <- aexpr
    x <- optionMaybe $ try (do
        spaces
        string "STEP"
        spaces
        a3 <- aexpr
        return a3)
    case x of
        Nothing -> return $ ForCom c (a1, a2, (NumExpr 1))
        Just s  -> return $ ForCom c (a1, a2, s)

nextCom :: Parser Com
nextCom = do
    string "NEXT"
    spaces
    c <- anyChar
    return $ NextCom c

inputCom :: Parser Com
inputCom = do
    string "INPUT"
    spaces
    s <- sexpr
    case s of
        (ConcatExpr (LiteralExpr s) (ToStringExpr (VarExpr c))) -> return $ InputCom s c
        (ToStringExpr (VarExpr c)) -> return $ InputCom "" c
        _ -> fail "Invalid input command"

goSubCom :: Parser Com
goSubCom = do
    string "GOSUB"
    spaces
    i <- integer
    return $ GoSubCom i

returnCom :: Parser Com
returnCom = string "RETURN" >> return ReturnCom

dimCom :: Parser Com
dimCom = do
    string "DIM"
    spaces
    as <- commaSep arrExpr
    return $ DimCom as 

seqCom :: Parser Com
seqCom = do
    c1 <- normalCom
    spaces
    char ':'
    spaces
    c2 <- com
    return $ SeqCom c1 c2

remCom :: Parser Com
remCom = do {string "REM"; many $ noneOf "\n"; return RemCom;}

normalCom :: Parser Com
normalCom = try remCom <|> printCom <|> letCom <|> endCom <|> try gotoCom <|> 
            try goSubCom <|> try ifCom <|> forCom <|> nextCom <|> inputCom 
            <|> returnCom
            <|> dimCom

com = try seqCom <|> normalCom

line :: Parser (Integer, Com)
line = do 
    i <- integer
    spaces
    c <- com
    -- spaces wil consume newline, don't use
    (many (char ' ')) 
    ((const ()) <$> char '\n') <|> eof
    return (i, c)

lines = many1 line

parseLines :: String -> Either ParseError [(Integer, (Com, Integer))]
parseLines = (fmap (addNextLines . (sortOn fst))) . parse
    where parse = runParser Parser.lines () ""

-- after interpreting a command, the interpreter can then get the number of the
-- command immediately following it to increment the PC (if a goto didn't
-- happen)
addNextLines :: [(Integer, Com)] -> [(Integer, (Com, Integer))]
addNextLines [] = []
addNextLines [(i, c)] = [(i, (c, -1))]
addNextLines ((i, c) : xs) = (i, (c, i2)) : addNextLines xs
    where (i2, c2) = head xs

-- returns the program and the number of the first instruction
parseProgram :: String -> Either ParseError (Map Integer (Com, Integer), Integer)
parseProgram str = fmap go (parseLines str)
    where go ls = (fromList ls, (fst.head) ls)
