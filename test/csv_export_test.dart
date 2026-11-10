import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/domain/csv_export.dart';

void main() {
  test('plain cells are unchanged', () => expect(Csv.cell('abc'), 'abc'));
  test('commas, quotes and newlines are quoted', () {
    expect(Csv.cell('a,b'), '"a,b"');
    expect(Csv.cell('say "hi"'), '"say ""hi"""');
    expect(Csv.cell('a\nb'), '"a\nb"');
  });
  test('formula-looking text is neutralised', () {
    expect(Csv.cell('=SUM(A1)'), "'=SUM(A1)");
    expect(Csv.cell('@x'), "'@x");
  });
  test('null becomes empty; numbers stay numbers', () {
    expect(Csv.row([null, 3, 'x']), ',3,x');
  });
  test('table has BOM and CRLF', () {
    final t = Csv.table([['a'], ['b']]);
    expect(t.startsWith('﻿'), isTrue);
    expect(t, '﻿a\r\nb\r\n');
  });
  test('Persian text passes through', () => expect(Csv.cell('احمدی'), 'احمدی'));
}
