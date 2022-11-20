module Parser (module Parser) where

import Text.Parsec
import Text.Parsec.String
import Expr
import Control.Monad
import Data.Char

integer :: Parser Integer
integer = read <$> many1 digit

anyString :: Parser String
anyString = many1 anyChar

numExpr :: Parser Aexpr
numExpr = NumExpr <$> integer

anyAlpha :: Parser Char
anyAlpha = do
    c <- anyChar
    guard (isAlpha c)
    return c

varExpr :: Parser Aexpr
varExpr = VarExpr <$> anyAlpha

aexprComb :: Char -> (Aexpr -> Aexpr -> Aexpr) -> Parser Aexpr
aexprComb symb expr = do
    a1 <- try aexprParens <|> try numExpr <|> try varExpr
    spaces
    char symb
    spaces
    a2 <- aexpr
    return $ expr a1 a2

sumExpr :: Parser Aexpr
sumExpr = aexprComb '+' SumExpr

prodExpr :: Parser Aexpr
prodExpr = aexprComb '*' ProdExpr

aexprParens :: Parser Aexpr
aexprParens = do
    char '('
    spaces
    a <- aexpr
    spaces
    char ')'
    return a

aexpr :: Parser Aexpr
aexpr = try prodExpr <|> try sumExpr <|> try numExpr <|> try varExpr <|> try aexprParens
{-
let :: Parser Com
let = do
    string "LET"
    spaces
    s <- many1 char
    spaces
    char '='
    spaces
    e <- aexpr
    return $ LetCom s e
    -}