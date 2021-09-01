/*
2021-09-01 LG

Pierwszy draft implementacji algorytmu rozwiązującego problem komiwojażera.
Algorytm jak i implementacja może zawierać błędy logiczne, wrzucam żeby nie zginęło :)

Idea:
Począwszy od 4 węzłów wzwyż możemy drogę podzielić na 3 etapy
1. Punkt początkowy
2. Punkt końcowy
3. Punkty pośrednie

Przykład dla 4 - AXYB i AYXB
Przykład dla 5 - AXYZB, AXZYB, AYXZB, AYZXB, AZXYB i AZYXB

Te drogi mają wspólne początki i końce, przechodzą wszystkie również przez te same węzły, mają jednak różne sumy wag.
Zakładam że można eliminować we wszsytkich kombinacjach te fragmenty, które mają mniejszą wagę.
Budując drzewo od dołu mając dwie gałęzie AXYB i AYXB mogę wyeliminować tę, która ma większą wagę.
Poza wagą różnią się tylko kolejnością odwiedzenia węzłów pośrednich.

W ten sposób już od 4 poziomu jestem w stanie eliminować gałęzie po wadze grupując je po węźle początkowym, końcowym i węzłach pośrednich (te bez wskazania na kolejność, właściwie to posortowane).

Przykład dla poziomu 4:

węzeł	waga	grupowanie	wybór 

ACDB	11		A,B,CD		ACDB
ADCB	12		A,B,CD		eliminacja
ABDC	13		A,C,BD		ABDC
ADBC	14		A,C,BD		eliminacja
ABCD	15		A,D,BC		ABCD
ACBD	16		A,D,BC		eliminacja
BCDA	17		B,A,CD		BCDA
BDCA	18		B,A,CD		eliminacja
BADC	19		B,C,AD		BADC
BDAC	20		B,C,AD		eliminacja
BACD	21		B,D,AC		BACD
BCAD	22		B,D,AC		eliminacja
CBDA	99		C,A,BD		eliminacja
CDBA	98		C,A,BD		CDBA
CADB	97		C,B,AD		eliminacja
CDAB	96		C,B,AD		CDAB
CABD	95		C,D,AB		eliminacja
CBAD	94		C,D,AB		CBAD
DBCA	93		D,A,BC		eliminacja
DCBA	92		D,A,BC		DCBA
DACB	91		D,B,AC		eliminacja
DCAB	90		D,B,AC		DCAB
DABC	89		D,C,AB		eliminacja
DBAC	88		D,C,AB		wybór

Po eliminacjach rozszerzam do 5 poziomu w oparciu o dostępne drogi, znowu grupuję i elimnuję i tak do końca

*/

-- przykładowe dane początkowe
drop table if exists wagi
go
create table wagi(miasto1 int, miasto2 int, waga int)

;with miasta as
(select number + 1 m
from master.dbo.spt_values
where type = 'P' and number < 10 -- ilość węzłów
)

insert into wagi(miasto1, miasto2, waga)
select m1.m,m2.m,(m1.m * m2.m) % 100 -- waga pseudolosowa
from miasta m1
inner join miasta m2
on m1.m <> m2.m


------------------------------------------

drop table if exists przebieg
go
create table przebieg(krok int,miasto_pierwsze int,miasto_ostatnie int,miasta_posrednie varchar(1700),przebieg varchar(1700),waga int, elim bit)
go
create clustered columnstore index csix_temp ON przebieg
go

-- inicjalne wypełnienie przebiegu do 4 węzła już z eliminacją

insert into przebieg(krok ,miasto_pierwsze ,miasto_ostatnie ,miasta_posrednie ,przebieg, waga, elim)
select krok,miasto_pierwsze,miasto_ostatnie,miasta_posrednie,przebieg,waga
	,iif(row_number() over(partition by miasto_pierwsze,miasto_ostatnie,miasta_posrednie order by waga) = 1, 0, 1) -- jesli nie pierwszy to do eliminacji
from
(
	select
		 1 as krok
		,w1.miasto1 as miasto_pierwsze
		,w3.miasto2 as miasto_ostatnie
		,iif(w2.miasto1 < w3.miasto1
						,concat(cast(w2.miasto1 as varchar(1700)),',',cast(w3.miasto1 as varchar(1700)))
						,concat(cast(w3.miasto1 as varchar(1700)),',',cast(w2.miasto1 as varchar(1700)))
			) as miasta_posrednie
		,concat(cast(w1.miasto1 as varchar(1700)),','
				,cast(w2.miasto1 as varchar(1700)),','
				,cast(w3.miasto1 as varchar(1700)),','
				,cast(w3.miasto2 as varchar(1700))) as przebieg
		,w1.waga + w2.waga + w3.waga as waga 
	from  wagi w1
	inner join wagi w2
		on w1.miasto2 = w2.miasto1
			and w1.miasto1 <> w2.miasto2
	inner join wagi w3
		on w2.miasto2 = w3.miasto1
			and w1.miasto1 <> w3.miasto1
			and w1.miasto1 <> w3.miasto2
			and w2.miasto1 <> w3.miasto2
) x


-- iteracje >= 2 dla poziomów >=5

declare @i int = 2 -- aktualna iteracja
declare @i_max int = (select count(1) - 2 from (select miasto1 from wagi union select miasto2 from wagi) x) -- max ilosc iteracji bazująca na count distinct wezłów

while @i < @i_max

begin

	--- dodanie liści 
	insert into przebieg(krok ,miasto_pierwsze ,miasto_ostatnie ,miasta_posrednie ,przebieg, waga)
	select
		 @i krok
		,p.miasto_pierwsze
		,w.miasto2 as miasto_ostatnie
		,(select 
			string_agg(cast(value as varchar(1700)), ',') within group (order by value asc) 
				from (select value from string_split (p.miasta_posrednie, ',' ) 
						union all select p.miasto_ostatnie
					) x
			) miasta_posrednie  -- obliczenie na nowo miast posrednich posortowanych od najmniejszych zeby mozna bylo po nich grupowac
		,concat(p.przebieg, ',',cast(w.miasto2 as varchar(1700))) as przebieg -- obliczenie przebiegu
		,p.waga + w.waga as waga -- obliczenie wagi
	from przebieg p
	inner join wagi w
		on p.miasto_ostatnie = w.miasto1
		and not exists (select top(1) null from
			(select value from string_split ( p.przebieg , ',' )x
			where x.value = w.miasto2
			) y) -- miasto do ktorego sie laczymy nie powinno juz byc w historii przebiegu
	where p.krok = @i - 1 -- poprzedni krok
		and p.elim = 0 -- tylko rokujące
	
	-- zaznaczenie gałęzi do eliminacji
	update x
		set elim = iif(x.rn=1, 0, 1)
	from (select krok, elim, row_number() over(partition by miasto_pierwsze,miasto_ostatnie,miasta_posrednie order by waga) as rn from przebieg) x
	where x.krok = @i 
	
	set @i = @i + 1

end


-- najkrótsza droga
select top(1) * from przebieg
order by krok desc ,waga
