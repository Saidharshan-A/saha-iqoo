import 'package:equatable/equatable.dart';

import '../models/patient.dart';

// ── Events ───────────────────────────────────────────────────

abstract class PatientEvent extends Equatable {
  const PatientEvent();

  @override
  List<Object?> get props => [];
}

class LoadPatients extends PatientEvent {
  const LoadPatients();
}

class SearchPatients extends PatientEvent {
  const SearchPatients(this.query);
  final String query;

  @override
  List<Object?> get props => [query];
}

class AddPatient extends PatientEvent {
  const AddPatient(this.patient);
  final Patient patient;

  @override
  List<Object?> get props => [patient];
}

class UpdatePatient extends PatientEvent {
  const UpdatePatient(this.patient);
  final Patient patient;

  @override
  List<Object?> get props => [patient];
}

class DeletePatient extends PatientEvent {
  const DeletePatient(this.patientId);
  final String patientId;

  @override
  List<Object?> get props => [patientId];
}

class LinkAbha extends PatientEvent {
  const LinkAbha(this.patientId);
  final String patientId;

  @override
  List<Object?> get props => [patientId];
}

// ── States ───────────────────────────────────────────────────

abstract class PatientState extends Equatable {
  const PatientState();

  @override
  List<Object?> get props => [];
}

class PatientInitial extends PatientState {
  const PatientInitial();
}

class PatientLoading extends PatientState {
  const PatientLoading();
}

class PatientsLoaded extends PatientState {
  const PatientsLoaded({
    required this.patients,
    required this.totalCount,
    required this.unsyncedCount,
    this.screeningsCount = 0,
  });

  final List<Patient> patients;
  final int totalCount;
  final int unsyncedCount;
  final int screeningsCount;

  @override
  List<Object?> get props => [patients, totalCount, unsyncedCount, screeningsCount];
}

class PatientOperationSuccess extends PatientState {
  const PatientOperationSuccess(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class PatientError extends PatientState {
  const PatientError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}
