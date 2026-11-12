import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/school_subject_utils.dart';

void main() {
  group('school_subject_utils - Prefix-tvätt och semantik', () {
    test('cleanLessonTitle tvättar Lektion och Lektion: skiftlägesokänsligt', () {
      expect(cleanLessonTitle('Lektion sv'), 'sv');
      expect(cleanLessonTitle('Lektion: idh'), 'idh');
      expect(cleanLessonTitle('lektion Ombyte'), 'Ombyte');
      expect(cleanLessonTitle('LEKTION: Rast'), 'Rast');
      expect(cleanLessonTitle('Engelska'), 'Engelska');
    });

    test('classifyScheduleSemantic klassificerar rast, lunch, ombyte och lektion', () {
      expect(classifyScheduleSemantic('Lektion rast'), ScheduleSemanticType.rast);
      expect(classifyScheduleSemantic('Lektion: Rast'), ScheduleSemanticType.rast);
      expect(classifyScheduleSemantic('paus'), ScheduleSemanticType.rast);
      expect(classifyScheduleSemantic('Lektion lunch'), ScheduleSemanticType.lunch);
      expect(classifyScheduleSemantic('Lunch'), ScheduleSemanticType.lunch);
      expect(classifyScheduleSemantic('Lektion Ombyte'), ScheduleSemanticType.ombyte);
      expect(classifyScheduleSemantic('Ombyte'), ScheduleSemanticType.ombyte);
      expect(classifyScheduleSemantic('Lektion sv'), ScheduleSemanticType.lesson);
      expect(classifyScheduleSemantic('Lektion: Matematik'), ScheduleSemanticType.lesson);
    });

    test('expandSchoolSubjectTitle expanderar alla 22 grundskoleämnen och lämnar okända orörda', () {
      expect(expandSchoolSubjectTitle('Lektion idh'), 'Idrott och hälsa');
      expect(expandSchoolSubjectTitle('sv'), 'Svenska');
      expect(expandSchoolSubjectTitle('Sva'), 'Svenska som andraspråk');
      expect(expandSchoolSubjectTitle('Sv/Sva'), 'Svenska');
      expect(expandSchoolSubjectTitle('Ma'), 'Matematik');
      expect(expandSchoolSubjectTitle('En'), 'Engelska');
      expect(expandSchoolSubjectTitle('Mu'), 'Musik');
      expect(expandSchoolSubjectTitle('Bl'), 'Bild');
      expect(expandSchoolSubjectTitle('Sl'), 'Slöjd');
      expect(expandSchoolSubjectTitle('Hkk'), 'Hem- och konsumentkunskap');
      expect(expandSchoolSubjectTitle('Tk'), 'Teknik');
      expect(expandSchoolSubjectTitle('NO'), 'Naturorienterande ämnen');
      expect(expandSchoolSubjectTitle('SO'), 'Samhällsorienterande ämnen');
      expect(expandSchoolSubjectTitle('Fy'), 'Fysik');
      expect(expandSchoolSubjectTitle('Ke'), 'Kemi');
      expect(expandSchoolSubjectTitle('Bi'), 'Biologi');
      expect(expandSchoolSubjectTitle('Ge'), 'Geografi');
      expect(expandSchoolSubjectTitle('Hi'), 'Historia');
      expect(expandSchoolSubjectTitle('Re'), 'Religionskunskap');
      expect(expandSchoolSubjectTitle('Sh'), 'Samhällskunskap');
      expect(expandSchoolSubjectTitle('Mspr'), 'Moderna språk');
      expect(expandSchoolSubjectTitle('M2'), 'Moderna språk');
      expect(expandSchoolSubjectTitle('Mspr/M2'), 'Moderna språk');
      expect(expandSchoolSubjectTitle('EV'), 'Elevens val');
      expect(expandSchoolSubjectTitle('Ment'), 'Mentorstid');
      expect(expandSchoolSubjectTitle('HARV1000X'), 'HARV1000X');
    });

    test('expandSchoolSubjectTitle med calendarDescription för kurskod', () {
      expect(
        expandSchoolSubjectTitle('HARV1000X', calendarDescription: 'Kurs: HARV1000X'),
        'HARV1000X',
      );
      expect(
        expandSchoolSubjectTitle('HARV1000X', calendarDescription: 'Kurs: Hantverksorientering'),
        'Hantverksorientering',
      );
    });
  });

  group('Korrigering 6d.4 — Titeltvätt för gymnasiekoder', () {
    test('Tvättar gymnasiekoder med understreck och klasskod ("mentorstid_tek2" -> "Mentorstid" + "tek2")', () {
      final res = cleanAndExpandSubjectTitle('mentorstid_tek2');
      expect(res.subject, 'Mentorstid');
      expect(res.classCode, 'tek2');
    });

    test('Tvättar kurskod med understreck och klasskod ("fysik 1_TE24b" -> "Fysik 1" + "TE24b")', () {
      final res = cleanAndExpandSubjectTitle('fysik 1_TE24b');
      expect(res.subject, 'Fysik 1');
      expect(res.classCode, 'TE24b');
    });

    test('Tvättar grundskoleförkortning med klasskod ("sv_tek2" -> "Svenska" + "tek2")', () {
      final res = cleanAndExpandSubjectTitle('sv_tek2');
      expect(res.subject, 'Svenska');
      expect(res.classCode, 'tek2');
    });

    test('Ersätter understreck med mellanslag och gör första bokstaven versal ("idrott_och_hälsa" -> "Idrott och hälsa")', () {
      final res = cleanAndExpandSubjectTitle('idrott_och_hälsa');
      expect(res.subject, 'Idrott och hälsa');
      expect(res.classCode, isNull);
    });

    test('Bevarar kursnamn som Matematik 2c utan att misstolka "2c" som klasskod', () {
      final res = cleanAndExpandSubjectTitle('Matematik 2c');
      expect(res.subject, 'Matematik 2c');
      expect(res.classCode, isNull);
    });

    test('Okänt mönster lämnas oförändrat ("HARV1000X")', () {
      final res = cleanAndExpandSubjectTitle('HARV1000X');
      expect(res.subject, 'HARV1000X');
      expect(res.classCode, isNull);
    });

    test('Tvättar bort Lektion:-prefix och hanterar klasskod ("Lektion: mentorstid_tek2")', () {
      final res = cleanAndExpandSubjectTitle('Lektion: mentorstid_tek2');
      expect(res.subject, 'Mentorstid');
      expect(res.classCode, 'tek2');
    });
  });
}
