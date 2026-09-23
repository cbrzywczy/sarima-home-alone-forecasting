# Prognozowanie szeregów czasowych: „Kevin sam w domu” i temperatura w Polsce

<img src="https://media1.tenor.com/m/6RRvzdMyDoAAAAAC/home-alone-kevin-mccallister.gif" alt="Kevin McCallister krzyczy" align="right" width="360">

> ### Który model najlepiej przewiduje grudniowy szczyt wyszukiwań „Kevin sam w domu”?

Projekt z Analizy Szeregów Czasowych (WNE UW, 2026) porównuje modele na dwóch szeregach. Pierwszy to popularność frazy „Kevin sam w domu” w Google, z wyraźną sezonowością. Drugi to średnioroczna temperatura w Polsce, bez sezonowości.

**Dane:** Google Trends z lat 2004–2025 (264 miesiące) i temperatura z lat 1901–2025 (125 lat)

**Modele:** SARIMA, Holt-Winters, ARIMA, Holt, SES, metoda naiwna, błądzenie losowe z dryfem

**Testy:** ADF z testem Breuscha-Godfreya, Ljunga-Boxa, Jarque-Bera, LR, ANOVA i Kruskala-Wallisa dla sezonowości

**Ocena:** prognozy out-of-sample, MAE, RMSE i MAPE ex post

<img src="https://cdn.jsdelivr.net/gh/devicons/devicon@v2.16.0/icons/r/r-original.svg" width="16" alt="R">&nbsp; `forecast` `tseries` `urca` `lmtest`

<br clear="right">

## „Kevin sam w domu”

![Popularność frazy „Kevin sam w domu”](charts/kevin_szereg.png)

Czarna linia to indeks Google Trends, czerwona to ten sam szereg po usunięciu sezonowości.

- Szczyt przypada zawsze na grudzień. Trend rośnie do ok. 2022 roku.
- Próba ucząca: 2004–2024. Próba testowa: 2025.
- Wybrany model: **SARIMA(0,0,1)(1,0,0)[12]**. Test Ljunga-Boxa (p = 0,020) wskazuje resztkową autokorelację.
- **Holt-Winters addytywny** ma mniejsze błędy absolutne: MAE 1,95 i RMSE 3,33. SARIMA ma mniejszy błąd procentowy: MAPE 35,2% wobec 44,7%.
- Wariant multiplikatywny Holta-Wintersa odpada, bo szereg zawiera zera.
- Grudzień 2025: wartość rzeczywista 91, Holt-Winters 80,7, SARIMA 77,0.

| Dekompozycja | Sezonowość |
|---|---|
| ![Dekompozycja](charts/kevin_dekompozycja.png) | ![Sezonowość](charts/kevin_sezonowosc.png) |
| Szereg rozłożony na trend, powtarzalny wzór sezonowy i resztę. | Wartości z kolejnych lat pogrupowane według miesięcy. Pozioma kreska to średnia miesiąca. Grudzień wyraźnie dominuje. |

![Prognozy out-of-sample](charts/kevin_prognozy.png)

Prognozy na 2025 rok na tle danych rzeczywistych. Oba modele trafiają w grudniowy szczyt, ale go zaniżają.

## Temperatura w Polsce

- Szereg ma wyraźny trend rosnący.
- Próba ucząca: 1901–2023. Próba testowa: 2024–2025.
- Wybrany model: **ARIMA(4,0,1)**. Reszty bez autokorelacji (Ljung-Box p = 0,36). Test LR: składnik MA(1) istotnie poprawia ARIMA(4,0,0) (p < 0,001).
- ARIMA ma mniejsze błędy niż Holt: RMSE 0,757 wobec 0,772, MAPE 5,1% wobec 6,6%.
- Najmniejszy błąd ex post ma **metoda naiwna** (RMSE 0,655). Najlepsze dopasowanie in-sample ma Holt.
- Prognoza ARIMA na lata 2026–2028: 9,6 °C, 9,3 °C, 9,6 °C.

| Trend | Prognozy |
|---|---|
| ![Trend temperatury](charts/temp_trend.png) | ![Prognozy temperatury](charts/temp_prognozy.png) |
| Temperatura roczna, średnia ruchoma i trend liniowy. Według trendu liniowego temperatura wzrosła od 1901 roku o 1,8 °C. | Prognozy na lata 2024–2025. Żaden model nie przewidział rekordowo ciepłego 2024 roku. |

## Kod

Cała analiza jest w jednym skrypcie [`projekt_asc.R`](projekt_asc.R).

| | Fragment | Zawartość |
|:-:|---|---|
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@v2.16.0/icons/r/r-original.svg" width="18"> | [Temperatura](projekt_asc.R#L42-L701) | trend, dekompozycja, Holt i modele ekstrapolacyjne, dobór ARIMA, test LR, ADF, diagnostyka reszt, prognozy |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@v2.16.0/icons/r/r-original.svg" width="18"> | [Kevin&nbsp;sam&nbsp;w&nbsp;domu](projekt_asc.R#L703-L1311) | dekompozycja, Holt-Winters, dobór SARIMA, ADF po różnicowaniu, testy sezonowości, diagnostyka reszt, prognozy |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@v2.16.0/icons/r/r-original.svg" width="18"> | [Tabele](projekt_asc.R#L1312-L1536) | tabele do raportu, podsumowanie liczbowe |

```r
# w katalogu repozytorium
source("projekt_asc.R")
```

Skrypt instaluje brakujące pakiety do `Rlib/`. Wyniki zapisuje w `latex/`.

## Dane

- [Google Trends](https://trends.google.com/trends/explore?date=all&geo=PL&q=Kevin%20sam%20w%20domu): fraza „Kevin sam w domu”, Polska → [`sezonowy/kevin2004teraz.csv`](sezonowy/kevin2004teraz.csv)
- [World Bank Climate Change Knowledge Portal](https://climateknowledgeportal.worldbank.org/country/poland): seria CRU, 1901–2024 → [`niesezonowy/dane/worldbank.json`](niesezonowy/dane/worldbank.json)
- [IMGW-PIB, dane publiczne](https://danepubliczne.imgw.pl/): rok 2025 → [`niesezonowy/dane/sredniorocznaT.csv`](niesezonowy/dane/sredniorocznaT.csv)

## Licencja

Kod: [MIT](LICENSE). Wykresy: CC BY 4.0.
