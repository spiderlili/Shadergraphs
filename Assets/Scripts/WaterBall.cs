using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

public class WaterBall : MonoBehaviour
{
    [SerializeField] private ParticleSystem waterBallParticleSystem;
    [SerializeField] private AnimationCurve speedAnimationCurve;
    [SerializeField] private float speed = 0.4f;
    [SerializeField] private ParticleSystem splashPrefab;
    [SerializeField] private ParticleSystem spillPrefab;
    [SerializeField] private float stopThrowDistanceThresholdFromTarget = 0.4f;
    [SerializeField] private float spillWaterOnHitAngleThreshold = 30f;
    [SerializeField] private float scaleUpSpeed = 1.0f;
    
    // Start the throw animation
    public void Throw(Vector3 target)
    {
        StopAllCoroutines();
        StartCoroutine(ThrowCoroutine(target));
    }

    // TODO: Scale up the waterball when first summoned
    public void ScaleUp()
    {
        StartCoroutine(ScaleUpCoroutine());
    }

    IEnumerator ScaleUpCoroutine()
    {
        float lerp = 0;
        Vector3 startScale = Vector3.zero;
        Vector3 endScale = new Vector3(1.0f, 1.0f, 1.0f);
        while (lerp < 1) {
            transform.localScale = Vector3.Lerp(startScale, endScale, lerp);
            lerp += Time.deltaTime * scaleUpSpeed;
            yield return null; // Pause here and carry on next frame
        }
    }
    
    // Controls the water ball for throwing: lerp the start position to target position using specified animation curve to move the waterball object
    IEnumerator ThrowCoroutine(Vector3 target)
    {
        float lerp = 0;
        Vector3 startPos = transform.position;
        
        while (lerp < 1) {
            transform.position = Vector3.Lerp(startPos, target, speedAnimationCurve.Evaluate(lerp)); // Evaluate gives the corresponding value at time(lerp)
            float magnitude = (transform.position - target).magnitude;
            
            // When at a small enough distance from the target: stop throwing
            if (magnitude < stopThrowDistanceThresholdFromTarget) {
                break;
            }
            lerp += Time.deltaTime * speed;
            yield return null;
        }
        
        // Stop the water ball & instantiate splash water vfx for magic sequence
        waterBallParticleSystem.Stop(false, ParticleSystemStopBehavior.StopEmittingAndClear);
        ParticleSystem splash = Instantiate(splashPrefab, target, quaternion.identity);
        Vector3 forward = target - startPos;
        forward.y = 0;
        splash.transform.forward = forward;

        // Check if the water ball has hit the target at a steep enough angle, if yes: instantiate the spill water vfx
        if (Vector3.Angle(startPos - target, Vector3.up) > spillWaterOnHitAngleThreshold) {
            ParticleSystem spill = Instantiate(spillPrefab, target, quaternion.identity);
            spill.transform.forward = forward;
        }
        
        Destroy(gameObject, 0.5f);
    }
}
