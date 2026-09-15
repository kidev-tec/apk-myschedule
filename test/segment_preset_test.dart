import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/segment/segment_preset.dart';

void main() {
  group('SegmentPreset', () {
    test('byId retorna preset correto', () {
      final beauty = SegmentPreset.byId('beauty');
      expect(beauty.id, 'beauty');
      expect(beauty.label, 'Estética & Beleza');
      expect(beauty.icon, Icons.face_retouching_natural);
    });

    test('byId desconhecido retorna primeiro (beauty) como fallback', () {
      final fallback = SegmentPreset.byId('inexistente');
      expect(fallback.id, 'beauty');
    });

    test('todos os 10 presets têm id, label, icon, cores e serviços', () {
      for (final preset in SegmentPreset.all) {
        expect(preset.id, isNotEmpty);
        expect(preset.label, isNotEmpty);
        expect(preset.icon, isNotNull);
        expect(preset.primary, isNotNull);
        expect(preset.primaryPressed, isNotNull);
        expect(preset.secondary, isNotNull);
        // outros: vetor de serviços sugeridos pode ser vazio (other)
        expect(preset.suggestedServices, isA<List>());
      }
    });

    test('beauty tem 3 serviços sugeridos com duration/price', () {
      final beauty = SegmentPreset.byId('beauty');
      expect(beauty.suggestedServices.length, 3);
      for (final svc in beauty.suggestedServices) {
        expect(svc.name, isNotEmpty);
        expect(svc.durationMin, greaterThan(0));
        expect(svc.priceCents, greaterThan(0));
      }
    });

    test('other tem serviços sugeridos vazios', () {
      final other = SegmentPreset.byId('other');
      expect(other.suggestedServices, isEmpty);
    });

    test('SegmentPresets.beauty alias funciona', () {
      expect(SegmentPresets.beauty.id, 'beauty');
    });
  });
}