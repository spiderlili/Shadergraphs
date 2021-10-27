using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

public class WaterBall : MonoBehaviour
{
    [SerializeField] private ParticleSystem waterBallParticleSystem;
    [SerializeField] private AnimationCurve speedAnimationCurve;
    [SerializeField] private float speed;
    [SerializeField] private ParticleSystem splashPrefab;
    [SerializeField] private ParticleSystem spillPrefab;

    public void Throw(Vector3 target)
    {
        StopAllCoroutines();
        StartCoroutine(ThrowCoroutine(target));
    }

    IEnumerator ThrowCoroutine(Vector3 target)
    {
        float lerp = 0;
        Vector3 startPos = transform.position;
        while (lerp < 1) {
            transform.position = Vector3.Lerp(startPos, target, speedAnimationCurve.Evaluate(lerp)); // Evaluate gives the corresponding value at time(lerp)
            float magnitude = (transform.position - target).magnitude;
            if (magnitude < 0.4f) {
                break;
            }
            lerp += Time.deltaTime * speed;
            yield return null;
        }
        
        waterBallParticleSystem.Stop(false, ParticleSystemStopBehavior.StopEmittingAndClear);
        ParticleSystem splash = Instantiate(splashPrefab, target, quaternion.identity);
        Vector3 forward = target - startPos;
        forward.y = 0;
        splash.transform.forward = forward;

        if (Vector3.Angle(startPos - target, Vector3.up) > 30) {
            ParticleSystem spill = Instantiate(spillPrefab, target, quaternion.identity);
            spill.transform.forward = forward;
        }
        
        Destroy(gameObject, 0.5f);
    }
}
