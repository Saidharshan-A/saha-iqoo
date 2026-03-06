import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/services/abha_service.dart';
import '../../../core/utils/logger.dart';
import '../repos/patient_repo.dart';
import 'patient_event_state.dart';

export 'patient_event_state.dart';

/// BLoC that manages Patient feature state.
///
/// Translates [PatientEvent]s into [PatientState]s by delegating
/// to [PatientRepository] for persistence and [AbhaService] for
/// ABHA ID linking.
class PatientBloc extends Bloc<PatientEvent, PatientState> {
  PatientBloc({
    PatientRepository? patientRepo,
    AbhaService? abhaService,
  })  : _repo = patientRepo ?? PatientRepository(),
        _abha = abhaService ?? AbhaService(),
        super(const PatientInitial()) {
    on<LoadPatients>(_onLoad);
    on<SearchPatients>(_onSearch);
    on<AddPatient>(_onAdd);
    on<UpdatePatient>(_onUpdate);
    on<DeletePatient>(_onDelete);
    on<LinkAbha>(_onLinkAbha);
  }

  final PatientRepository _repo;
  final AbhaService _abha;
  static const _tag = 'PatientBloc';

  // ── Handlers ───────────────────────────────────────────────

  Future<void> _onLoad(LoadPatients event, Emitter<PatientState> emit) async {
    emit(const PatientLoading());
    try {
      final patients = await _repo.getAllPatients();
      final total = await _repo.getTotalCount();
      final unsynced = await _repo.getUnsyncedCount();
      final screenings = await _repo.getScreeningsCount();
      emit(PatientsLoaded(
        patients: patients,
        totalCount: total,
        unsyncedCount: unsynced,
        screeningsCount: screenings,
      ));
    } catch (e, st) {
      Log.e('Failed to load patients', tag: _tag, error: e, stackTrace: st);
      emit(PatientError(e.toString()));
    }
  }

  Future<void> _onSearch(
      SearchPatients event, Emitter<PatientState> emit) async {
    emit(const PatientLoading());
    try {
      final patients = await _repo.searchPatients(event.query);
      final total = await _repo.getTotalCount();
      final unsynced = await _repo.getUnsyncedCount();
      final screenings = await _repo.getScreeningsCount();
      emit(PatientsLoaded(
        patients: patients,
        totalCount: total,
        unsyncedCount: unsynced,
        screeningsCount: screenings,
      ));
    } catch (e, st) {
      Log.e('Search failed', tag: _tag, error: e, stackTrace: st);
      emit(PatientError(e.toString()));
    }
  }

  Future<void> _onAdd(AddPatient event, Emitter<PatientState> emit) async {
    try {
      await _repo.createPatient(event.patient);
      Log.i('Patient added: ${event.patient.id}', tag: _tag);
      emit(const PatientOperationSuccess('Patient registered successfully'));
      add(const LoadPatients());
    } catch (e, st) {
      Log.e('Add failed', tag: _tag, error: e, stackTrace: st);
      emit(PatientError(e.toString()));
    }
  }

  Future<void> _onUpdate(
      UpdatePatient event, Emitter<PatientState> emit) async {
    try {
      await _repo.updatePatient(event.patient);
      emit(const PatientOperationSuccess('Patient updated'));
      add(const LoadPatients());
    } catch (e, st) {
      Log.e('Update failed', tag: _tag, error: e, stackTrace: st);
      emit(PatientError(e.toString()));
    }
  }

  Future<void> _onDelete(
      DeletePatient event, Emitter<PatientState> emit) async {
    try {
      await _repo.deletePatient(event.patientId);
      emit(const PatientOperationSuccess('Patient removed'));
      add(const LoadPatients());
    } catch (e, st) {
      Log.e('Delete failed', tag: _tag, error: e, stackTrace: st);
      emit(PatientError(e.toString()));
    }
  }

  Future<void> _onLinkAbha(
      LinkAbha event, Emitter<PatientState> emit) async {
    try {
      final abhaNumber = await _abha.linkAbha(event.patientId);
      Log.i('ABHA linked: $abhaNumber → ${event.patientId}', tag: _tag);
      emit(PatientOperationSuccess('ABHA $abhaNumber linked'));
      add(const LoadPatients());
    } catch (e, st) {
      Log.e('ABHA link failed', tag: _tag, error: e, stackTrace: st);
      emit(PatientError('ABHA linking failed: $e'));
    }
  }
}
