// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_party.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinancePartyAdapter extends TypeAdapter<FinanceParty> {
  @override
  final int typeId = 14;

  @override
  FinanceParty read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinanceParty(
      id: fields[0] as String,
      name: fields[1] as String,
      partyType: fields[2] as String,
      phone: fields[3] as String,
      email: fields[4] as String,
      taxIdentifier: fields[5] as String,
      active: fields[6] as bool
    );
  }

  @override
  void write(BinaryWriter writer, FinanceParty obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.partyType)
      ..writeByte(3)
      ..write(obj.phone)
      ..writeByte(4)
      ..write(obj.email)
      ..writeByte(5)
      ..write(obj.taxIdentifier)
      ..writeByte(6)
      ..write(obj.active);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancePartyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
