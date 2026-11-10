import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/utils/name_check.dart';

void main() {
  test('case, spacing and Arabic/Persian look-alikes are one name', () {
    expect(NameCheck.key(' Ahmad  Khan '), NameCheck.key('ahmad khan'));
    expect(NameCheck.key('احمدي'), NameCheck.key('احمدی'));
    expect(NameCheck.key('كابل'), NameCheck.key('کابل'));
  });
  test('different names stay different', () {
    expect(NameCheck.key('Ali'), isNot(NameCheck.key('Alim')));
  });
}
